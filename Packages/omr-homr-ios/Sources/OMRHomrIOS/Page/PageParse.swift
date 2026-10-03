// SPDX-License-Identifier: AGPL-3.0-or-later
//
// omr-sheet-cam — full-page parse (page pipeline, milestone 3): page -> preprocessing -> SegNet -> staff detection
// -> per-staff crop/dewarp + decode -> homr voices -> SMF + noteLayout.
// Port of liebharc/homr @ 7d97c3cee4ad772b50266fdf9dc78bbf9064701e (AGPL-3.0): homr/main.py (process_image,
// detect_staffs_in_image, filter_predictions applied to the preprocessed page) and homr/staff_parsing.py
// (parse_staffs, parse_staff_image) + homr/staff_parsing_tromr.py (predict_best position filter).

import Foundation
import OMRPNG

/// Everything the page path produced, for diagnostics / oracle comparisons. `result` is what
/// `OMRHomrIOS.parseSheetMusicWithLayout(gray8:width:height:)` returns.
public struct PageParseResult: Sendable {
    public struct StageTiming: Sendable, Equatable {
        public var stage: String
        public var ms: Double
    }

    public var result: ParseSheetMusicResult
    /// homr `parse_staffs` output: one stream per voice (all rows of that voice, each row followed by `newline`,
    /// then `remove_duplicated_symbols`). `noteLayout[k].symbolIndex` indexes the concatenation of all voices
    /// in order (voice 0 first).
    public var voices: [[EncodedSymbol]]
    /// Per staff in `layout.staffs` order: raw decoder output (EOS excluded).
    public var staffSymbols: [[EncodedSymbol]]
    /// Per staff: after homr's position filter (non-grand staffs drop `lower*` symbols).
    public var filteredStaffSymbols: [[EncodedSymbol]]
    public var layout: PageStaffLayout
    /// Autocrop rect in input pixels and the preprocessed page size (1920 wide) the geometry refers to.
    public var crop: PagePipeline.Rect
    public var pageWidth: Int
    public var pageHeight: Int
    public var timings: [StageTiming]
}

/// Loaded page-path models: SegNet (fp16), encoder (fp16), decoder (fp32, CPU). Create once and reuse; a parse
/// runs sessions sequentially (not reentrant — serialize calls).
public final class PageInferenceSession: @unchecked Sendable {
    public let segnet: SegNetSession
    public let staff: StaffInferenceSession
    private let lock = NSLock()

    public init(segnet: SegNetSession, staff: StaffInferenceSession) {
        self.segnet = segnet
        self.staff = staff
    }

    /// Reuse already created ORT backends (e.g. the app's warmed sessions). The decoder backend must be CPU.
    public convenience init(
        segnet: any ORTSessionBackend,
        encoder: any ORTSessionBackend,
        decoder: any ORTSessionBackend,
        vocabulary: HomrVocabulary
    ) throws {
        let staff = try StaffInferenceSession(encoder: encoder, decoder: decoder, vocabulary: vocabulary)
        self.init(segnet: SegNetSession(backend: segnet), staff: staff)
    }

    /// Raw 8-bit gray page (row-major, no padding, upright; e.g. a camera photo's luma) -> full homr page parse.
    /// `progress` (optional) is called on the parsing thread after preprocessing, after every SegNet tile,
    /// after staff detection, after each staff's encoder + decoder, and once at the end (fraction 1.0).
    public func parsePage(
        gray8: Data, width: Int, height: Int, progress: PageParseProgressHandler? = nil
    ) throws -> PageParseResult {
        try parsePage(progress: progress) { try PagePipeline.preprocess(gray8: gray8, width: width, height: height) }
    }

    /// Color page (R, G, B, X bytes per pixel; see `PagePipeline.preprocess(rgbx:width:height:bytesPerRow:)`),
    /// preprocessed in color like homr, then the same parse as `parsePage(gray8:)`.
    public func parsePage(
        rgbx: Data, width: Int, height: Int, bytesPerRow: Int, progress: PageParseProgressHandler? = nil
    ) throws -> PageParseResult {
        try parsePage(progress: progress) {
            try PagePipeline.preprocess(rgbx: rgbx, width: width, height: height, bytesPerRow: bytesPerRow)
        }
    }

    private func parsePage(
        progress: PageParseProgressHandler?, preprocess: () throws -> PagePipeline.PreprocessedPage
    ) throws -> PageParseResult {
        lock.lock()
        defer { lock.unlock() }
        var timings: [PageParseResult.StageTiming] = []
        var t = ProcessInfo.processInfo.systemUptime
        func mark(_ stage: String) {
            let now = ProcessInfo.processInfo.systemUptime
            let ms: Double = (now - t) * 1000
            timings.append(.init(stage: stage, ms: ms))
            t = now
        }

        let page = try preprocess()
        mark("preprocess")
        progress?(PageParseProgress(stage: .preprocess, completed: 1, total: 1))
        let onTile: ((Int, Int) -> Void)? = progress.map { report -> (Int, Int) -> Void in
            { done, total in report(PageParseProgress(stage: .segnet, completed: done, total: total)) }
        }
        let seg = try PagePipeline.segment(page, segnet: segnet, onTile: onTile)
        mark("segnet")
        // SegNet sub-stage split (device diagnostics; flows into Copy-as-prompt stages).
        timings.append(.init(stage: "segnet_pack", ms: segnet.lastPackMs))
        timings.append(.init(stage: "segnet_run", ms: segnet.lastRunMs))
        timings.append(.init(stage: "segnet_run_first", ms: segnet.lastFirstBatchRunMs))
        timings.append(.init(stage: "segnet_argmax", ms: segnet.lastArgmaxMs))
        let layout = try PagePipeline.detectStaffs(segmentation: seg, width: page.width, height: page.height)
        mark("staffs")
        progress?(PageParseProgress(stage: .staffs, completed: 1, total: 1))
        let image = PagePipeline.maskedPage(page.preprocessed, noiseMask: layout.noiseMask)
        let toInput = PageToInputMapping(crop: page.crop, pageWidth: page.width, pageHeight: page.height)

        var raw: [[EncodedSymbol]] = []
        var filtered: [[EncodedSymbol]] = []
        var canvasMs = 0.0
        for (i, s) in layout.staffs.enumerated() {
            let tc = ProcessInfo.processInfo.systemUptime
            let prepared = try StaffPrepare.prepareStaffImage(page: image, width: page.width, height: page.height,
                                                              geometry: s.geometry)
            let canvas = try StaffPrepare.canvas(prepared)
            canvasMs += (ProcessInfo.processInfo.systemUptime - tc) * 1000
            var symbols = try staff.decodeStaff(tensor: StaffTensor.fromCanvas(canvas))
            // homr dda4d2f parse_staff_image: image_coordinates = page_to_input(staff_to_page(center)).
            PagePipeline.attachPositions(&symbols, toPage: prepared.toPage, toInput: toInput)
            timings.append(.init(stage: "decode_s\(i)_enc", ms: staff.lastEncoderMs))
            timings.append(.init(stage: "decode_s\(i)_dec", ms: staff.lastDecoderMs))
            raw.append(symbols)
            filtered.append(SymbolCleanup.positionFilter(symbols, isGrandstaff: s.isGrandstaff))
            progress?(PageParseProgress(stage: .decode, completed: raw.count, total: layout.staffs.count))
        }
        mark("decode")
        timings.append(.init(stage: "decode_canvas", ms: canvasMs))

        let voices = PagePipeline.voices(layout: layout, staffSymbols: filtered)
        let boxes = AttentionNoteBoxProvider(noteheads: layout.symbols["noteheads"] ?? [],
                                             noteheadHeight: layout.averageNoteHeadHeight, toInput: toInput)
        let result = PagePipeline.render(voices: voices, grandstaffVoices: PagePipeline.grandstaffVoices(layout),
                                         boxProvider: boxes)
        mark("render")
        progress?(PageParseProgress(stage: .render, completed: 1, total: 1))
        return PageParseResult(
            result: result, voices: voices, staffSymbols: raw, filteredStaffSymbols: filtered, layout: layout,
            crop: page.crop, pageWidth: page.width, pageHeight: page.height, timings: timings)
    }

    /// PNG page (decoded like homr's `cv2.imread` + BGR2GRAY) -> `parsePage(gray8:width:height:)`.
    public func parsePage(png: Data, progress: PageParseProgressHandler? = nil) throws -> PageParseResult {
        let g = try PagePipeline.decodePagePNG(png)
        return try parsePage(gray8: Data(g.pixels), width: g.width, height: g.height, progress: progress)
    }
}

#if canImport(CONNXRuntime) || canImport(CONNXRuntimeApple)
extension PageInferenceSession {
    /// Pinned models (models.lock names) from `modelsDirectory`, else `$OMR_MODELS_DIR`, else `models/` in
    /// `bundle` (default `Bundle.main`). SegNet + encoder use the CoreML EP on Apple (CPU fallback), CPU on Linux;
    /// the decoder always runs on CPU (never CoreML, never a cache).
    ///
    /// SegNet runs the CoreML NeuralNetwork format (`SegNetSession.openBackend`, legacy flags 0x000); the
    /// encoder keeps MLProgram (CPU+GPU).
    ///
    /// - Parameter segnetCacheDirectory: IGNORED (silent no-op, kept so existing callers still compile and
    ///   run). SegNet uses the NeuralNetwork format with no compiled-model cache: create ~0.1–0.2 s, and the
    ///   MLProgram format a cache would need returns all zeros for SegNet. Nothing is created in the folder.
    /// - Parameter encoderCacheDirectory: CoreML compiled-model cache folder for the encoder (the app's
    ///   `<AppSupport>/coreml-cache/<sha256>/`), nil (default) = no cache. Cache key = SHA-256 of the model
    ///   file. Used only for the CoreML attempt, not the CPU fallback; ignored on Linux. See
    ///   `ORTCSession.init(modelURL:provider:cacheDirectory:cacheKey:)` for what the folder owner must handle.
    public static func load(
        modelsDirectory: URL? = nil,
        bundle: Bundle? = nil,
        segnetCacheDirectory: URL? = nil,
        encoderCacheDirectory: URL? = nil
    ) throws -> PageInferenceSession {
        let dir = try PageModels.resolveDirectory(modelsDirectory, bundle: bundle)
        let files = try PageModels.files(in: dir)
        let vocab = try TokenizerLoader.loadVocabulary(bundle: nil)
        _ = segnetCacheDirectory // intentionally unused: SegNet (NeuralNetwork) has no CoreML cache
        let seg = try PageModels.acceleratedSegNet(files.segnet)
        let enc = try PageModels.accelerated(files.encoder, cacheDirectory: encoderCacheDirectory)
        let dec = try ORTCSession(modelURL: files.decoder, provider: .cpu)
        return try PageInferenceSession(segnet: seg, encoder: enc, decoder: dec, vocabulary: vocab)
    }
}
#endif

/// Pinned model discovery for the page path (same rules as the app's `ModelWarmup`).
public enum PageModels {
    public struct Files: Sendable, Equatable {
        public var segnet: URL
        public var encoder: URL
        public var decoder: URL
    }

    /// `explicit`, else `$OMR_MODELS_DIR`, else `models/` in `bundle` (default `Bundle.main`).
    public static func resolveDirectory(_ explicit: URL?, bundle: Bundle? = nil) throws -> URL {
        if let explicit { return explicit }
        if let env = ProcessInfo.processInfo.environment["OMR_MODELS_DIR"], !env.isEmpty {
            return URL(fileURLWithPath: env, isDirectory: true)
        }
        if let b = (bundle ?? Bundle.main).url(forResource: "models", withExtension: nil) { return b }
        throw OMRError.modelsNotBundled("no models/ in the app bundle and OMR_MODELS_DIR unset")
    }

    /// `segnet_*_fp16.onnx`, `encoder_*_fp16.onnx`, `decoder_*.onnx` (not fp16) in `dir`.
    public static func files(in dir: URL) throws -> Files {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
        func pick(_ prefix: String, fp16: Bool) throws -> URL {
            let hit = names.last { n in
                n.hasPrefix(prefix) && n.hasSuffix(".onnx") && n.hasSuffix("_fp16.onnx") == fp16
            }
            guard let hit else {
                throw OMRError.modelsNotBundled("\(prefix)*\(fp16 ? "_fp16" : "").onnx not in \(dir.path)")
            }
            return dir.appendingPathComponent(hit)
        }
        return Files(segnet: try pick("segnet_", fp16: true), encoder: try pick("encoder_", fp16: true),
                     decoder: try pick("decoder_", fp16: false))
    }

    #if canImport(CONNXRuntime) || canImport(CONNXRuntimeApple)
    /// Encoder: `.coreML` (+ optional compiled-model cache) on Apple, else / on failure `.cpu` (never with a
    /// cache). Not for SegNet (`acceleratedSegNet`).
    static func accelerated(_ url: URL, cacheDirectory: URL? = nil) throws -> ORTCSession {
        #if canImport(CONNXRuntimeApple)
        if let s = try? ORTCSession(modelURL: url, provider: .coreML, cacheDirectory: cacheDirectory) { return s }
        #endif
        return try ORTCSession(modelURL: url, provider: .cpu)
    }

    /// SegNet: `SegNetSession.openBackend(.coreML)` (NeuralNetwork 0x000, never cached) on Apple, else /
    /// on failure `.cpu`.
    static func acceleratedSegNet(_ url: URL) throws -> ORTCSession {
        #if canImport(CONNXRuntimeApple)
        if let s = try? SegNetSession.openBackend(modelURL: url, provider: .coreML) { return s }
        #endif
        return try SegNetSession.openBackend(modelURL: url, provider: .cpu)
    }
    #endif
}

extension PagePipeline {
    /// PNG page bytes -> gray; non-PNG input (JPEG / HEIC camera photos) -> `OMRError.unsupportedImageFormat`.
    static func decodePagePNG(_ data: Data) throws -> (pixels: [UInt8], width: Int, height: Int) {
        let sig: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        guard data.count >= 8, Array(data.prefix(8)) == sig else {
            throw OMRError.unsupportedImageFormat(
                "page imageData is not PNG; decode the photo yourself and call "
                + "parseSheetMusicWithLayout(gray8:width:height:) with 8-bit gray pixels")
        }
        do { return try StaffTensor.decodeGrayPNG(data) } catch {
            throw OMRError.unsupportedImageFormat("PNG decode failed: \(error)")
        }
    }

    /// PNG bytes -> R, G, B, X (4 bytes per pixel, no row padding) for `parsePage(rgbx:...)`; gray PNGs
    /// expand to R = G = B (alpha dropped, like `cv2.imread(IMREAD_COLOR)`).
    public static func decodeRGBXPNG(_ data: Data) throws -> (pixels: Data, width: Int, height: Int) {
        let img = try PNGDecoder.decode([UInt8](data))
        let n = img.width * img.height
        var out = Data(count: n * 4)
        out.withUnsafeMutableBytes { raw in
            let o = raw.bindMemory(to: UInt8.self)
            for i in 0..<n {
                let s = i * img.channels
                if img.channels >= 3 {
                    o[i * 4] = img.pixels[s]; o[i * 4 + 1] = img.pixels[s + 1]; o[i * 4 + 2] = img.pixels[s + 2]
                } else {
                    let v = img.pixels[s]
                    o[i * 4] = v; o[i * 4 + 1] = v; o[i * 4 + 2] = v
                }
                o[i * 4 + 3] = 255
            }
        }
        return (out, img.width, img.height)
    }

    /// homr `filter_predictions`: `cv2.bitwise_and(preprocessed, preprocessed, mask=mask)`.
    public static func maskedPage(_ preprocessed: [UInt8], noiseMask: [UInt8]?) -> [UInt8] {
        guard let mask = noiseMask, mask.count == preprocessed.count else { return preprocessed }
        var out = preprocessed
        for i in out.indices where mask[i] == 0 { out[i] = 0 }
        return out
    }

    /// homr `prepare_staff_image` for one detected staff: 1280x256 uint8 canvas (TrOMR input before normalization).
    public static func staffCanvas(page: [UInt8], width: Int, height: Int, staff: PageStaffLayout.Staff) throws -> [UInt8] {
        let r = try StaffPrepare.prepareStaffImage(page: page, width: width, height: height, geometry: staff.geometry)
        return try StaffPrepare.canvas(r)
    }

    /// Voices whose staffs are grand staffs (their streams carry `upper` + `lower` positions -> 2 SMF tracks).
    static func grandstaffVoices(_ layout: PageStaffLayout) -> Set<Int> {
        Set(layout.staffs.filter(\.isGrandstaff).map(\.voice))
    }

    /// homr `parse_staffs` join: per voice, rows in order, empty staffs skipped, `newline` after each row, then
    /// `remove_duplicated_symbols`. `staffSymbols` are position-filtered and in `layout.staffs` order.
    static func voices(layout: PageStaffLayout, staffSymbols: [[EncodedSymbol]]) -> [[EncodedSymbol]] {
        var out: [[EncodedSymbol]] = []
        for v in 0..<layout.voices {
            var stream: [EncodedSymbol] = []
            for (s, symbols) in zip(layout.staffs, staffSymbols) where s.voice == v && !symbols.isEmpty {
                stream.append(contentsOf: symbols)
                stream.append(EncodedSymbol(rhythm: "newline"))
            }
            out.append(SymbolCleanup.removeDuplicatedSymbols(stream))
        }
        return out
    }

    /// Voices -> one SMF (format 1, 480 TPQ; track 0 conductor, then one track per staff: a voice is one staff,
    /// a grand-staff voice two, top to bottom) + `noteLayout` from the same sorted note list.
    static func render(voices: [[EncodedSymbol]], grandstaffVoices: Set<Int>, boxProvider: (any NoteBoxProvider)? = nil,
                       writer: SMFWriter = SMFWriter()) -> ParseSheetMusicResult {
        let tpq = Int(SMFWriter.ticksPerQuarter)
        var events: [SymbolMIDIMapping.SourcedNoteEvent] = []
        var base = 0
        var staffOffset = 0
        for (v, stream) in voices.enumerated() {
            var ev = SymbolMIDIMapping.sourcedNoteEvents(from: stream, tpq: tpq, resetCursorOnClef: false)
            for i in ev.indices {
                ev[i].symbolIndex += base
                ev[i].event.staff += staffOffset
            }
            events.append(contentsOf: ev)
            base += stream.count
            staffOffset += grandstaffVoices.contains(v) ? 2 : 1
        }
        events.sort(by: SymbolMIDIMapping.canonicalOrder)
        let staffCount = max(1, staffOffset)
        let midi = writer.write(notes: events.map(\.event), staffCount: staffCount)
        var layout = NoteLayout.midiFallback(from: events)
        var source = LayoutSource.midiFallback
        var warnings: [String] = []
        if let provider = boxProvider, !layout.isEmpty {
            let all = voices.flatMap { $0 }
            var boxed = 0
            for i in layout.indices {
                let si = layout[i].symbolIndex
                guard all.indices.contains(si), let r = provider.pageRect(forSymbolAt: si, symbol: all[si]), !r.isNull else { continue }
                layout[i].pageRect = r
                boxed += 1
            }
            if boxed == layout.count {
                source = .attention
            } else {
                warnings.append("layout: midi-fallback (boxes for \(boxed)/\(layout.count) notes)")
            }
        } else {
            warnings.append("layout: midi-fallback (no attention boxes; pageRect is .null)")
        }
        if events.isEmpty { warnings.append("no sounding notes decoded") }
        return ParseSheetMusicResult(
            midi: midi, noteLayout: layout, layoutSource: source, staffCount: staffCount, warnings: warnings)
    }

    /// Fills `pagePoint` / `imageCoordinates` of every decoded symbol that has an attention center.
    static func attachPositions(_ symbols: inout [EncodedSymbol], toPage: StaffToPageMapping, toInput: PageToInputMapping) {
        for i in symbols.indices {
            guard let c = symbols[i].attentionCenter else { continue }
            let p = toPage.toPage(c)
            guard p.x.isFinite, p.y.isFinite else { continue }
            symbols[i].pagePoint = p
            symbols[i].imageCoordinates = toInput.toInput(p)
        }
    }
}

public extension OMRHomrIOS {
    /// Full page from raw 8-bit gray pixels (row-major, `width * height` bytes, no row padding, upright) ->
    /// SMF (one track per staff) + `noteLayout`. Loads the pinned models once (`PageInferenceSession.load()`:
    /// bundle `models/` or `$OMR_MODELS_DIR`) and reuses them. Heavy: call off the main thread.
    /// - Throws: `OMRError.invalidPixelBuffer`, `OMRError.modelsNotBundled`, `PageStaffDetectionError`
    ///   (no noteheads / staffs on the page), ORT errors.
    static func parseSheetMusicWithLayout(gray8: Data, width: Int, height: Int) throws -> ParseSheetMusicResult {
        try PagePipeline.validate(byteCount: gray8.count, width: width, height: height)
        return try parseSheetMusicWithLayout(gray8: gray8, width: width, height: height, session: defaultPageSession())
    }

    /// Same with caller-owned sessions (e.g. built from the app's warmed ORT backends).
    static func parseSheetMusicWithLayout(
        gray8: Data, width: Int, height: Int, session: PageInferenceSession
    ) throws -> ParseSheetMusicResult {
        try session.parsePage(gray8: gray8, width: width, height: height).result
    }

    /// Full page from PNG bytes (gray / RGB / RGBA, decoded like homr's `cv2.imread`).
    static func parseSheetMusicWithLayout(png: Data) throws -> ParseSheetMusicResult {
        let g = try PagePipeline.decodePagePNG(png)
        return try parseSheetMusicWithLayout(gray8: Data(g.pixels), width: g.width, height: g.height)
    }

    /// Shared lazily loaded page session (models loaded on first use).
    static func defaultPageSession() throws -> PageInferenceSession {
        try PageSessionCache.shared.get()
    }
}

final class PageSessionCache: @unchecked Sendable {
    static let shared = PageSessionCache()
    private let lock = NSLock()
    private var session: PageInferenceSession?

    func get() throws -> PageInferenceSession {
        lock.lock()
        defer { lock.unlock() }
        if let session { return session }
        #if canImport(CONNXRuntime) || canImport(CONNXRuntimeApple)
        let s = try PageInferenceSession.load()
        session = s
        return s
        #else
        throw OMRError.sessionNotConfigured("no ONNX Runtime linked (Linux: scripts/fetch-ort, docs/ORT-LINUX.md)")
        #endif
    }
}
