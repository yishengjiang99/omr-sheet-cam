import Foundation
import OMRHomrIOS
import UIKit

/// What the service needs from a page session: `PageInferenceSession` in the app, fakes in tests.
protocol PageParser: AnyObject, Sendable {
    func parse(gray8: Data, width: Int, height: Int) throws -> PageParseOutput
    /// Same, reporting pipeline progress (`PageParseProgress`, on the parsing thread).
    func parse(gray8: Data, width: Int, height: Int, progress: PageParseProgressHandler?) throws -> PageParseOutput
}

extension PageParser {
    /// Parsers without stage reporting: no intermediate progress (the service still reports 1.0 on success).
    func parse(gray8: Data, width: Int, height: Int, progress: PageParseProgressHandler?) throws -> PageParseOutput {
        try parse(gray8: gray8, width: width, height: height)
    }
}

/// A value plus how long it took (Sendable across detached tasks).
struct Timed<T: Sendable>: Sendable {
    var value: T
    var ms: Double

    static func run(_ body: () throws -> T) rethrows -> Timed<T> {
        let t = DispatchTime.now()
        let v = try body()
        return Timed(value: v, ms: ModelWarmup.ms(since: t))
    }
}

struct PageParseOutput: Sendable {
    struct Stage: Equatable, Sendable {
        var name: String
        var ms: Double
    }

    var result: ParseSheetMusicResult
    var stages: [Stage] = []
}

extension PageInferenceSession: PageParser {
    func parse(gray8: Data, width: Int, height: Int) throws -> PageParseOutput {
        try parse(gray8: gray8, width: width, height: height, progress: nil)
    }

    func parse(gray8: Data, width: Int, height: Int, progress: PageParseProgressHandler?) throws -> PageParseOutput {
        let r = try parsePage(gray8: gray8, width: width, height: height, progress: progress)
        return PageParseOutput(result: r.result, stages: r.timings.map { .init(name: $0.stage, ms: $0.ms) })
    }
}

/// Full-page recognition: photo bytes → `Gray8Image` (EXIF upright, no row padding) →
/// `PageInferenceSession.parsePage(gray8:width:height:)` → `RecognitionOutcome`.
///
/// - Session: built lazily on the first parse from the launch warmup's ORT sessions
///   (`ModelWarmup.readyModels()`: SegNet + encoder fp16 on CoreML EP w/ CPU fallback, decoder
///   fp32 on CPU EP), then reused. A memory warning drops it (and the warmed sessions) so the next
///   parse rebuilds.
/// - One parse at a time (FIFO); decode and parse run in detached tasks, never on the main thread.
/// - Every parse writes a `recognition` / `page_parse` event to `DiagnosticsLog` (duration, image
///   size, staffCount, warnings, `phys_footprint` before / after / peak).
final class PageRecognitionService: RecognitionService, @unchecked Sendable {
    typealias SessionFactory = @Sendable () async throws -> any PageParser

    static let shared = PageRecognitionService()

    /// App default: a `PageInferenceSession` over the warmup's already created ORT sessions.
    static let warmedSession: SessionFactory = {
        let m = try await ModelWarmup.shared.readyModels()
        return try PageInferenceSession(
            segnet: m.segnet, encoder: m.encoderBackend, decoder: m.decoderBackend, vocabulary: m.vocabulary
        )
    }

    let engine: Engine
    private let center: NotificationCenter
    private var observer: NSObjectProtocol?

    init(
        factory: @escaping SessionFactory = PageRecognitionService.warmedSession,
        releaseShared: @escaping @Sendable () async -> Void = { await ModelWarmup.shared.releaseModels() },
        log: DiagnosticsLog = .shared,
        notificationCenter: NotificationCenter = .default,
        sampleInterval: TimeInterval = 0.1
    ) {
        let engine = Engine(factory: factory, releaseShared: releaseShared, log: log, sampleInterval: sampleInterval)
        self.engine = engine
        center = notificationCenter
        observer = notificationCenter.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil
        ) { _ in
            Task { await engine.dropSession(reason: "memory warning") }
        }
    }

    deinit {
        if let observer { center.removeObserver(observer) }
    }

    func recognize(imageData: Data) async -> RecognitionOutcome {
        await engine.recognize(imageData: imageData, progress: nil)
    }

    /// `progress` gets the page pipeline's fraction (0...1, never decreasing, 1.0 on success) from a
    /// background thread; hop to the main actor before touching UI (`RecognitionProgress`).
    func recognize(imageData: Data, progress: @escaping RecognitionProgressHandler) async -> RecognitionOutcome {
        await engine.recognize(imageData: imageData, progress: progress)
    }

    // MARK: - Pure helpers (unit-tested)

    /// staffCount 0, empty MIDI or no sounding notes → `.failed`; otherwise `.recognized`.
    static func outcome(for r: ParseSheetMusicResult, ms: Double) -> RecognitionOutcome {
        guard r.staffCount > 0 else { return .failed("no music staff found on the page (staffCount 0)") }
        guard !r.midi.isEmpty else { return .failed("recognizer returned empty MIDI") }
        guard !r.noteLayout.isEmpty else {
            return .failed("no notes recognized (\(r.staffCount) staff\(r.staffCount == 1 ? "" : "s"))")
        }
        return .recognized(RecognitionDetails(r, ms: ms))
    }

    static func fmt(_ v: Double) -> String { String(format: "%.1f", v) }

    /// Serializes parses and owns the lazily built session.
    actor Engine {
        private let factory: SessionFactory
        private let releaseShared: @Sendable () async -> Void
        private let log: DiagnosticsLog
        private let sampleInterval: TimeInterval
        private var session: (any PageParser)?
        private var busy = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        private var dropReason: String?
        /// Sessions built so far (tests: reuse / rebuild after a memory warning).
        private(set) var buildCount = 0
        private(set) var parseCount = 0

        init(factory: @escaping SessionFactory, releaseShared: @escaping @Sendable () async -> Void,
             log: DiagnosticsLog, sampleInterval: TimeInterval) {
            self.factory = factory
            self.releaseShared = releaseShared
            self.log = log
            self.sampleInterval = sampleInterval
        }

        var hasSession: Bool { session != nil }

        /// Drops the session (a parse in flight keeps its own reference and finishes).
        func dropSession(reason: String) async {
            let had = session != nil
            session = nil
            if had { dropReason = reason }
            await releaseShared()
            let mb = MemoryStats.snapshot().map { MemoryStats.mb($0.footprint) } ?? -1
            log.record(.warn, .recognition, "\(reason): dropped page session (had session: \(had)), footprint \(String(format: "%.0f", mb)) MB",
                       payload: ["kind": "page_session_drop", "reason": reason, "had_session": "\(had)",
                                 "footprint_mb": PageRecognitionService.fmt(mb)])
        }

        private func acquire() async {
            if !busy { busy = true; return }
            await withCheckedContinuation { waiters.append($0) }
        }

        private func release() {
            if waiters.isEmpty { busy = false } else { waiters.removeFirst().resume() }
        }

        func recognize(imageData: Data, progress: RecognitionProgressHandler?) async -> RecognitionOutcome {
            await acquire()
            defer { release() }
            // A task cancelled while queued must not burn a full parse when its turn arrives.
            guard !Task.isCancelled else { return .failed("cancelled") }
            let gate = progress.map { MonotonicProgress($0) }
            let outcome = await run(imageData, progress: gate)
            if case .recognized = outcome { gate?.report(ScanProgress(warmingUp: false, fraction: 1)) }
            return outcome
        }

        private func run(_ imageData: Data, progress: MonotonicProgress?) async -> RecognitionOutcome {
            parseCount += 1
            let t0 = DispatchTime.now()
            let before = MemoryStats.snapshot()
            let sampler = MemorySampler(interval: sampleInterval)
            sampler.start()
            var p: [String: String] = ["kind": "page_parse", "input_bytes": "\(imageData.count)", "parse_index": "\(parseCount)"]
            var outcome: RecognitionOutcome
            var staffs = "-", warnings = 0, image = "?"
            do {
                let decoded = try await Task.detached(priority: .userInitiated) {
                    try Timed.run { try Gray8Image.decode(imageData: imageData) }
                }.value
                let gray = decoded.value
                image = "\(gray.width)x\(gray.height)"
                p["image"] = image
                p["image_w"] = "\(gray.width)"
                p["image_h"] = "\(gray.height)"
                p["decode_ms"] = fmt(decoded.ms)
                p["exif_orientation"] = "\(gray.orientation)"
                p["source_format"] = gray.source

                let s: any PageParser
                if let session {
                    s = session
                    p["session"] = "reused"
                } else {
                    let tb = DispatchTime.now()
                    // The parse blocks on the launch warmup here (up to ~30 s) with no pipeline
                    // events; surface it as "Warming up… x%" instead of a stuck 0%.
                    if let gate = progress {
                        let warmupHandler: WarmupProgressHandler = { f in
                            gate.report(ScanProgress(warmingUp: true, fraction: f))
                        }
                        _ = await ModelWarmup.shared.attachProgressIfNeeded(warmupHandler)
                    }
                    s = try await factory()
                    session = s
                    buildCount += 1
                    p["session"] = dropReason.map { "rebuilt after \($0)" } ?? (buildCount == 1 ? "built" : "rebuilt")
                    p["session_build_ms"] = fmt(ModelWarmup.ms(since: tb))
                    p["session_warmup_wait_ms"] = fmt(await ModelWarmup.shared.lastReadyWaitMs)
                    dropReason = nil
                }

                let onStage: PageParseProgressHandler? = progress.map { gate -> PageParseProgressHandler in
                    { p in gate.report(ScanProgress(warmingUp: false, fraction: p.fraction)) }
                }
                let parsed = try await Task.detached(priority: .userInitiated) {
                    try Timed.run {
                        try s.parse(gray8: gray.pixels, width: gray.width, height: gray.height, progress: onStage)
                    }
                }.value
                let out = parsed.value, parseMs = parsed.ms
                let r = out.result
                staffs = "\(r.staffCount)"
                warnings = r.warnings.count
                p["parse_ms"] = fmt(parseMs)
                p["staff_count"] = staffs
                p["warnings_count"] = "\(warnings)"
                p["warnings"] = r.warnings.joined(separator: "; ")
                p["note_count"] = "\(r.noteLayout.count)"
                p["midi_bytes"] = "\(r.midi.count)"
                p["layout_source"] = r.layoutSource.rawValue
                if !out.stages.isEmpty {
                    p["stages"] = out.stages.map { "\($0.name)=\(String(format: "%.0f", $0.ms))" }.joined(separator: " ")
                }
                outcome = PageRecognitionService.outcome(for: r, ms: parseMs)
            } catch {
                outcome = .failed(String(describing: error))
                p["error"] = String(describing: error)
                p["error_type"] = String(reflecting: type(of: error))
            }

            let (sampledPeak, samples) = sampler.stop()
            let after = MemoryStats.snapshot()
            let totalMs = ModelWarmup.ms(since: t0)
            p["ms"] = fmt(totalMs)
            p["outcome"] = outcome.name
            if case let .failed(msg) = outcome, p["error"] == nil { p["error"] = msg }

            // Peak during this parse: the kernel's lifetime ledger peak if it moved, else the 100 ms samples.
            var peak = max(sampledPeak, before?.footprint ?? 0, after?.footprint ?? 0)
            var peakSource = "sampled"
            if let lb = before?.ledgerPeak, let la = after?.ledgerPeak, la > lb, la >= peak {
                peak = la
                peakSource = "ledger"
            }
            let beforeMB = before.map { MemoryStats.mb($0.footprint) } ?? -1
            let afterMB = after.map { MemoryStats.mb($0.footprint) } ?? -1
            let peakMB = MemoryStats.mb(peak)
            p["footprint_before_mb"] = fmt(beforeMB)
            p["footprint_after_mb"] = fmt(afterMB)
            p["peak_mb"] = fmt(peakMB)
            p["peak_source"] = peakSource
            p["sampled_peak_mb"] = fmt(MemoryStats.mb(sampledPeak))
            p["samples"] = "\(samples)"
            if let la = after?.ledgerPeak { p["ledger_peak_mb"] = fmt(MemoryStats.mb(la)) }
            if let av = after?.available { p["available_mb"] = fmt(MemoryStats.mb(av)) }

            var msg = String(format: "page parse %@: %.0f ms · %@ · staffs %@ · %d warning(s) · footprint %.0f → %.0f MB, peak %.0f MB (%@)",
                             outcome.name, totalMs, image, staffs, warnings, beforeMB, afterMB, peakMB, peakSource)
            let level: DiagnosticsEvent.Level
            if case let .failed(e) = outcome {
                level = .error
                msg += " · \(e)"
            } else {
                level = .info
            }
            log.record(level, .recognition, msg, payload: p)
            return outcome
        }

        private func fmt(_ v: Double) -> String { PageRecognitionService.fmt(v) }
    }
}

/// Forwards only increasing fractions (clamped to 0...1) to `handler`; thread-safe.
/// A phase change (warming up ⇄ reading) resets the high-water mark.
final class MonotonicProgress: @unchecked Sendable {
    private let handler: RecognitionProgressHandler
    private let lock = NSLock()
    private var last = -1.0
    private var lastWarmingUp = false

    init(_ handler: @escaping RecognitionProgressHandler) { self.handler = handler }

    func report(_ e: ScanProgress) {
        let f = min(max(e.fraction, 0), 1)
        lock.lock()
        if e.warmingUp != lastWarmingUp { last = -1; lastWarmingUp = e.warmingUp }
        guard f > last else { lock.unlock(); return }
        last = f
        lock.unlock()
        handler(ScanProgress(warmingUp: e.warmingUp, fraction: f))
    }
}
