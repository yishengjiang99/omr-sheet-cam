import Foundation
import ImageIO

// Host-facing scan API: pages in, one merged SMF out, with progress, cancellation, a failure
// taxonomy (stable telemetry reason codes) and a `ScanHost` seam for the app's own policy.

/// Where the pages came from (telemetry only).
public enum ScanSource: String, Sendable { case camera, photos, file, fixture }

public enum ScanPhase: String, Sendable { case warming, reading }

/// One progress report for a whole scan. `fraction` is 0...1, never decreases within a phase and
/// comes only from the warmup load progress (`.warming`) and the page pipeline (`.reading`; across
/// pages: `(page + pageFraction) / pageCount`). Nothing is invented between reports.
public struct ScanStatus: Equatable, Sendable {
    public var phase: ScanPhase
    public var fraction: Double
    /// Seconds of warmup remaining, only while `.warming` and when known.
    public var etaSeconds: Double?
    /// The warmup is reloading models after a memory-warning release (not the first load).
    public var isRewarm: Bool
    /// 0-based page being read, and the total.
    public var page: Int
    public var pageCount: Int

    public init(phase: ScanPhase, fraction: Double, etaSeconds: Double? = nil, isRewarm: Bool = false,
                page: Int = 0, pageCount: Int = 1) {
        self.phase = phase; self.fraction = fraction; self.etaSeconds = etaSeconds
        self.isRewarm = isRewarm; self.page = page; self.pageCount = pageCount
    }

    public var percent: Int { Int((min(max(fraction, 0), 1) * 100).rounded(.down)) }
}

/// Measurements for a whole scan (1...n pages), the field set the web scan telemetry and the
/// `page_parse` diagnostics event use.
public struct ScanDiagnostics: Equatable, Sendable {
    public var pages = 0
    public var totalMs = 0.0
    public var stageMs: [String: Double] = [:]
    public var staffCount = 0
    public var systemCount = 0
    public var voiceCount = 0
    public var rawTokens = 0
    public var filteredTokens = 0
    /// Per staff across all pages, parse order: post-filter tokens, raw tokens, encode+decode ms.
    public var perStaffTokens: [Int] = []
    public var perStaffRawTokens: [Int] = []
    public var perStaffMs: [Double] = []
    public var noteCount = 0
    public var midiBytes = 0
    public var warningCount = 0
    /// The last parsed page's layout source ("attention" / "midi-fallback").
    public var layoutSource = ""
    /// ORT execution providers ("coreML" / "cpu") of the warmed sessions; nil when unknown (fakes).
    public var backendSegnet: String?
    public var backendEncoder: String?
    public var backendDecoder: String?
    /// Set when the scan (or its last page) failed: one of `ScanError.reasonCode`.
    public var failureReason: String?

    public init() {}

    public var preprocessMs: Double { stageMs["preprocess"] ?? 0 }
    public var segnetMs: Double { stageMs["segnet"] ?? 0 }
    public var detectMs: Double { stageMs["staffs"] ?? 0 }
    public var encodeMs: Double { stageMs.filter { $0.key.hasPrefix("decode_s") && $0.key.hasSuffix("_enc") }.values.reduce(0, +) }
    public var decodeMs: Double { stageMs.filter { $0.key.hasPrefix("decode_s") && $0.key.hasSuffix("_dec") }.values.reduce(0, +) }

    mutating func add(_ d: RecognitionDetails) {
        pages += 1
        staffCount += d.staffCount
        noteCount += d.notes.count
        midiBytes += d.midi.count
        warningCount += d.warnings.count
        layoutSource = d.layoutSource
        guard let p = d.diagnostics else { return }
        systemCount += Set(p.staffSymbols.map(\.row)).count
        voiceCount += Set(p.staffSymbols.map(\.voice)).count
        rawTokens += p.staffSymbols.reduce(0) { $0 + $1.raw }
        filteredTokens += p.staffSymbols.reduce(0) { $0 + $1.filtered }
        perStaffTokens += p.staffSymbols.map(\.filtered)
        perStaffRawTokens += p.staffSymbols.map(\.raw)
        perStaffMs += p.perStaffMs
        for s in p.stages { stageMs[s.name, default: 0] += s.ms }
    }
}

public struct ScanResult: Equatable, Sendable {
    /// One Standard MIDI File (type 1, 480 TPQ): conductor track + one track per staff.
    public var midi: Data
    public var noteCount: Int
    /// Tracks that carry notes.
    public var trackCount: Int
    public var pageCount: Int
    /// Per recognized page, in order (note boxes for overlays, warnings, timings).
    public var pages: [RecognitionDetails]
    public var diagnostics: ScanDiagnostics
}

/// A failed scan, classified. `reasonCode` is the stable telemetry code.
public struct ScanError: Error, Equatable, Sendable, CustomStringConvertible {
    public enum Kind: String, Sendable {
        case cancelled, nothingRecognized, recognizerUnavailable, unreadableInput, failed
        /// The host's `didFinish` threw; `message` is the host's own user-facing text.
        case handOffFailed
    }

    public var kind: Kind
    public var message: String
    public var reasonCode: String
    public var diagnostics: ScanDiagnostics?

    public init(kind: Kind, message: String, reasonCode: String, diagnostics: ScanDiagnostics? = nil) {
        self.kind = kind; self.message = message; self.reasonCode = reasonCode; self.diagnostics = diagnostics
    }

    public var description: String { "\(kind.rawValue)(\(reasonCode)): \(message)" }

    public static let cancelled = ScanError(kind: .cancelled, message: "cancelled", reasonCode: "cancelled")

    /// Classifies a `RecognitionOutcome.failed` message into the kind + reason code taxonomy:
    /// `no_staff`, `empty_midi`, `no_notes`, `models_not_bundled`, `session_not_configured`,
    /// `tokenizer_missing`, `invalid_input`, `unsupported_format`, `parse_error`, `cancelled`.
    public static func classify(_ message: String) -> ScanError {
        let m = message.lowercased()
        func e(_ k: Kind, _ code: String) -> ScanError { ScanError(kind: k, message: message, reasonCode: code) }
        if m == "cancelled" { return .cancelled }
        if m.contains("no noteheads") || m.contains("no staffs found") || m.contains("no music staff") || m.contains("staffcount 0") {
            return e(.nothingRecognized, "no_staff")
        }
        if m.contains("empty midi") { return e(.failed, "empty_midi") }
        if m.contains("no notes recognized") || m.contains("no sounding notes") { return e(.nothingRecognized, "no_notes") }
        if m.contains("modelsnotbundled") || m.contains("models missing") { return e(.recognizerUnavailable, "models_not_bundled") }
        if m.contains("sessionnotconfigured") { return e(.recognizerUnavailable, "session_not_configured") }
        if m.contains("tokenizermissing") || m.contains("invalidvocabulary") { return e(.recognizerUnavailable, "tokenizer_missing") }
        if m.contains("unsupportedimageformat") { return e(.unreadableInput, "unsupported_format") }
        if m.contains("invalidpixelbuffer") || m.contains("not decodable") || m.contains("zero width or height")
            || m.contains("devicegray context") || m.contains("undecodable") {
            return e(.unreadableInput, "invalid_input")
        }
        return e(.failed, "parse_error")
    }
}

/// Events a host's telemetry sink receives, in the shape gbk's `ScanTelemetry` already logs.
public enum ScanEvent: Sendable {
    /// `width` / `height`: pixel size of the first page's image (no pixels or names), nil if unreadable.
    case started(source: ScanSource, pages: Int, width: Int?, height: Int?)
    case progress(ScanStatus)
    case completed(source: ScanSource, result: ScanResult, durationMs: Double)
    case failed(source: ScanSource, reasonCode: String, diagnostics: ScanDiagnostics?, durationMs: Double)
}

/// What a host app plugs in. All members have defaults.
public protocol ScanHost: Sendable {
    /// The scan produced `result`. Throwing fails the scan (e.g. the studio is not ready); it is
    /// never called for a cancelled scan.
    func didFinish(_ result: ScanResult) async throws
    /// Optional gate before a scan starts (quota, paywall). Return false to refuse; the runner
    /// throws `ScanError` with reason code `gated`.
    func shouldBeginScan() async -> Bool
    func telemetry(_ event: ScanEvent)
}

/// An error from `ScanHost.didFinish` that carries its own telemetry code and user-facing text.
public protocol ScanFailureReporting: Error {
    var scanReasonCode: String { get }
    var scanMessage: String { get }
}

public extension ScanHost {
    func shouldBeginScan() async -> Bool { true }
    func telemetry(_ event: ScanEvent) {}
}

/// Runs 1...n encoded page images (JPEG / PNG / HEIC bytes, EXIF honored) through a
/// `RecognitionService`, merges the per-page SMFs into one score (page 2 starts where page 1
/// ends), and hands the result to the host.
///
/// Cancellation: cancel the calling `Task`. The ORT parse cannot be aborted, so it stops at the
/// next checkpoint and its late result is dropped; `ScanHost.didFinish` is never called for a
/// cancelled scan. A page that fails classification is skipped; the scan fails only when no page
/// produced notes, or at once when the recognizer itself is unavailable (no models).
public struct ScanRunner: Sendable {
    public let service: any RecognitionService

    public init(service: any RecognitionService = PageRecognitionService.shared) {
        self.service = service
    }

    private static func pixelSize(_ data: Data) -> (Int, Int)? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = p[kCGImagePropertyPixelWidth] as? Int, let h = p[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (w, h)
    }

    @MainActor private static func warmedBackends() -> (String, String, String)? {
        guard let r = ModelWarmup.shared.report else { return nil }
        func provider(_ name: String) -> String { r.sessions.first { $0.name == name }?.provider ?? "unknown" }
        return (provider("segnet"), provider("encoder"), provider("decoder"))
    }

    @discardableResult
    public func run(
        pages: [Data], source: ScanSource = .photos, host: (any ScanHost)? = nil,
        onStatus: @escaping @Sendable (ScanStatus) -> Void = { _ in }
    ) async throws -> ScanResult {
        let t0 = DispatchTime.now()
        func elapsed() -> Double { Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000 }
        guard !pages.isEmpty else {
            throw ScanError(kind: .unreadableInput, message: "no pages", reasonCode: "invalid_input")
        }
        if let host, !(await host.shouldBeginScan()) {
            throw ScanError(kind: .failed, message: "scan not allowed", reasonCode: "gated")
        }
        let size = Self.pixelSize(pages[0])
        host?.telemetry(.started(source: source, pages: pages.count, width: size?.0, height: size?.1))
        let report = StatusGate(pageCount: pages.count) { status in
            onStatus(status)
            host?.telemetry(.progress(status))
        }

        var diagnostics = ScanDiagnostics()
        var merged = Score(parts: [])
        var details: [RecognitionDetails] = []
        var offset = 0.0
        var lastFailure: ScanError?

        func fail(_ error: ScanError) -> ScanError {
            var e = error
            diagnostics.totalMs = elapsed()
            diagnostics.failureReason = e.reasonCode
            e.diagnostics = diagnostics
            if e.kind != .cancelled {
                host?.telemetry(.failed(source: source, reasonCode: e.reasonCode, diagnostics: diagnostics, durationMs: diagnostics.totalMs))
            }
            return e
        }

        for (index, data) in pages.enumerated() {
            if Task.isCancelled { throw fail(.cancelled) }
            report.page = index
            let outcome = await service.recognizeUnlessCancelled(imageData: data, progress: { report.apply($0) })
            guard let outcome else { throw fail(.cancelled) }
            switch outcome {
            case .comingSoon:
                throw fail(ScanError(kind: .recognizerUnavailable, message: "no recognizer", reasonCode: "session_not_configured"))
            case let .failed(message):
                let failure = ScanError.classify(message)
                if failure.kind == .cancelled { throw fail(.cancelled) }
                if failure.kind == .recognizerUnavailable { throw fail(failure) }
                lastFailure = failure
            case let .recognized(d):
                guard let score = try? SMFReader.score(from: d.midi) else {
                    lastFailure = ScanError(kind: .failed, message: "unreadable MIDI from recognizer", reasonCode: "parse_error")
                    continue
                }
                diagnostics.add(d)
                if diagnostics.backendSegnet == nil, let b = await MainActor.run(body: { Self.warmedBackends() }) {
                    (diagnostics.backendSegnet, diagnostics.backendEncoder, diagnostics.backendDecoder) = b
                }
                details.append(d)
                merged.tempo = merged.tempo ?? score.tempo
                merged.key = merged.key ?? score.key
                merged.timeSig = merged.timeSig ?? score.timeSig
                var end = offset
                for (i, part) in score.parts.enumerated() {
                    let shifted = part.notes.map { n -> ScoreNote in
                        var n = n; n.onset += offset; end = max(end, n.onset + n.duration); return n
                    }
                    if i < merged.parts.count { merged.parts[i].notes += shifted }
                    else { merged.parts.append(ScorePart(name: part.name, program: part.program, notes: shifted)) }
                }
                offset = end
            }
        }
        if Task.isCancelled { throw fail(.cancelled) }
        guard merged.noteCount > 0 else {
            // A single page surfaces its own classified failure; several that all failed read as
            // "nothing recognized", with the last reason code kept for telemetry.
            let base = (pages.count == 1 ? lastFailure : nil)
                ?? ScanError(kind: .nothingRecognized, message: "no notes were recognized",
                             reasonCode: lastFailure?.reasonCode ?? "no_notes")
            throw fail(base)
        }
        diagnostics.totalMs = elapsed()
        let result = ScanResult(
            midi: SMFWriter.data(for: merged), noteCount: merged.noteCount,
            trackCount: merged.parts.filter { !$0.notes.isEmpty }.count, pageCount: pages.count,
            pages: details, diagnostics: diagnostics
        )
        report.finish()
        if let host {
            if Task.isCancelled { throw fail(.cancelled) }
            do { try await host.didFinish(result) } catch {
                let r = error as? ScanFailureReporting
                throw fail(ScanError(kind: .handOffFailed, message: r?.scanMessage ?? String(describing: error),
                                     reasonCode: r?.scanReasonCode ?? "handoff_failed"))
            }
        }
        host?.telemetry(.completed(source: source, result: result, durationMs: elapsed()))
        return result
    }
}

/// Maps the per-page `ScanProgress` stream onto whole-scan `ScanStatus` values: warming passes
/// through, reading is `(page + fraction) / pageCount`, and each phase never goes backward.
final class StatusGate: @unchecked Sendable {
    private let pageCount: Int
    private let emit: @Sendable (ScanStatus) -> Void
    private let lock = NSLock()
    private var _page = 0
    private var last: (phase: ScanPhase, fraction: Double)?

    init(pageCount: Int, emit: @escaping @Sendable (ScanStatus) -> Void) {
        self.pageCount = pageCount; self.emit = emit
    }

    var page: Int {
        get { lock.lock(); defer { lock.unlock() }; return _page }
        set { lock.lock(); _page = newValue; lock.unlock() }
    }

    func apply(_ p: ScanProgress) {
        lock.lock()
        let phase: ScanPhase = p.warmingUp ? .warming : .reading
        let raw = min(max(p.fraction, 0), 1)
        let fraction = phase == .warming ? raw : (Double(_page) + raw) / Double(pageCount)
        if let last, last.phase == phase, fraction <= last.fraction { lock.unlock(); return }
        last = (phase, fraction)
        let status = ScanStatus(phase: phase, fraction: fraction, etaSeconds: p.warmingUp ? p.etaSeconds : nil,
                                isRewarm: p.isRewarm, page: _page, pageCount: pageCount)
        lock.unlock()
        emit(status)
    }

    /// Ends exactly at 1.0 in the reading phase.
    func finish() {
        lock.lock()
        if let last, last.phase == .reading, last.fraction >= 1 { lock.unlock(); return }
        last = (.reading, 1)
        let status = ScanStatus(phase: .reading, fraction: 1, page: max(0, pageCount - 1), pageCount: pageCount)
        lock.unlock()
        emit(status)
    }
}
