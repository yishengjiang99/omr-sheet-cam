import Darwin
import Foundation
import OMRHomrIOS
import os

/// Launch-time background warmup of the three pinned homr models (models.lock), bundled into
/// `<App>.app/models/` by the "Bundle ONNX models" build phase.
///
/// - SegNet fp16: `SegNetSession.openBackend(provider: .coreML)` (CoreML EP NeuralNetwork, all compute
///   units, CPU EP fallback; MLProgram returns all zeros for SegNet). Encoder fp16:
///   `ORTCSession(provider: .coreML)` (MLProgram CPU+GPU, CPU EP fallback).
/// - Decoder fp32: `ORTCSession(provider: .cpu)` (locked rule; `DecoderSession` enforces it).
/// - One cheap dummy inference each: SegNet zeros `[1,3,320,320]`, Encoder zeros staff tile
///   `[1,1,256,1280]`, Decoder one step (BOS) over that encoder context.
/// - All ORT / CoreML work runs in a detached task, never on the main thread. State is published
///   on the main actor for the debug UI.
/// - Logs (`Logger`, subsystem = bundle id, category `warmup`): per-session create / first-run ms
///   and provider, `phys_footprint` MB after each session, total ms and peak MB.
///
/// Warmup step progress 0...1, called from the warmup worker thread.
typealias WarmupProgressHandler = @Sendable (Double) -> Void

/// Thread-safe multicast for warmup progress: the launch warmup starts without a watcher, and a
/// scan that arrives mid-warmup attaches its handler to the in-flight run.
private final class WarmupProgressBus: @unchecked Sendable {
    private let lock = NSLock()
    private var handlers: [WarmupProgressHandler] = []
    func add(_ h: @escaping WarmupProgressHandler) {
        lock.lock(); handlers.append(h); lock.unlock()
    }
    func broadcast(_ f: Double) {
        lock.lock(); let hs = handlers; lock.unlock()
        for h in hs { h(f) }
    }
    func clear() {
        lock.lock(); handlers.removeAll(); lock.unlock()
    }
}

/// One bus per process (the warmup is a singleton run).
private let warmupProgressBus = WarmupProgressBus()

/// Models dir: explicit argument, else `OMR_MODELS_DIR` (tests / CI), else the app bundle.
@MainActor
final class ModelWarmup: ObservableObject {
    enum State: Equatable {
        case idle, warming, ready
        case failed(String)
    }

    static let shared = ModelWarmup()

    @Published private(set) var state: State = .idle
    @Published private(set) var report: WarmupReport?
    /// Warm sessions, reused by `PageRecognitionService` and Gate-1.
    private(set) var models: WarmedModels?
    private var task: Task<WarmupReport?, Never>?
    /// ms the last `readyModels()` call spent inside (0 when already warm). Diagnostic only:
    /// lets the parse log split "session built" into warmup-wait vs actual build.
    private(set) var lastReadyWaitMs: Double = 0

    init() {}

    /// True once any warmup has completed. Tells a post-memory-warning re-warm apart from a
    /// first-ever warmup (launch owns that; tests with fake factories must never auto-start one).
    private(set) var hasWarmedOnce = false

    /// If a warmup is in-flight, failed (retry), or due for re-warm after a memory warning, attach
    /// `progress` to it — starting it when needed — and return true. Returns false when already
    /// warm, so the caller proceeds with no warmup phase. Never starts a first-ever warmup.
    func attachProgressIfNeeded(_ progress: @escaping WarmupProgressHandler) -> Bool {
        switch state {
        case .ready:
            return false
        case .warming, .failed:
            break
        case .idle:
            guard hasWarmedOnce else { return false }
        }
        start(progress: progress)
        return true
    }

    /// Starts the warmup once (re-runs only after a failure). Returns immediately; await the task
    /// value for the report. Never blocks the caller.
    /// `progress`, when given, is attached to the in-flight run (even one started earlier without a
    /// watcher, e.g. at app launch) and receives weighted 0...1 step fractions from the worker thread.
    @discardableResult
    func start(modelsDir: URL? = nil, progress: WarmupProgressHandler? = nil) -> Task<WarmupReport?, Never> {
        if let progress { warmupProgressBus.add(progress) }
        if let task, state != .idle, !isFailed { return task }
        state = .warming
        report = nil
        let worker = Task.detached(priority: .utility) { () -> Result<WarmedModels, Error> in
            Result { try ModelWarmup.run(modelsDir: modelsDir, progress: { warmupProgressBus.broadcast($0) }) }
        }
        let t = Task { [weak self] () -> WarmupReport? in
            let result = await worker.value
            warmupProgressBus.clear()
            guard let self else { return try? result.get().report }
            switch result {
            case let .success(m):
                self.models = m
                self.report = m.report
                self.state = .ready
                self.hasWarmedOnce = true
                return m.report
            case let .failure(error):
                self.state = .failed(String(describing: error))
                DiagnosticsLog.shared.record(
                    .error, .warmup, "warmup failed: \(error)",
                    payload: ["kind": "failed", "error": String(describing: error), "type": String(reflecting: type(of: error)),
                              "footprint_mb": String(format: "%.1f", ModelWarmup.physFootprintMB())]
                )
                return nil
            }
        }
        task = t
        return t
    }

    /// Warm sessions, starting the warmup if needed; suspends (never blocks) until ready.
    func readyModels(modelsDir: URL? = nil) async throws -> WarmedModels {
        let t0 = DispatchTime.now()
        defer { lastReadyWaitMs = ModelWarmup.ms(since: t0) }
        if let models, state == .ready { return models }
        _ = await start(modelsDir: modelsDir).value
        if let models, state == .ready { return models }
        throw WarmupError.notReady(debugLine)
    }

    /// Memory warning: forget the warm sessions so ORT / CoreML memory is freed once nothing else
    /// holds them; the next `readyModels()` warms up again. No-op while a warmup is running.
    func releaseModels() {
        guard state != .warming else { return }
        let had = models != nil
        models = nil
        task = nil
        state = .idle
        if had {
            DiagnosticsLog.shared.record(.warn, .warmup, "released warm sessions (memory warning)",
                                         payload: ["kind": "released", "footprint_mb": String(format: "%.1f", ModelWarmup.physFootprintMB())])
        }
    }

    private var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }

    /// One-line status for TestFlight testers (no console needed).
    var debugLine: String {
        switch state {
        case .idle: return "warmup: idle"
        case .warming: return "warmup: warming…"
        case .ready:
            guard let r = report else { return "warmup: ready" }
            return String(format: "warmup: ready %.0f ms, peak %.0f MB", r.totalMs, r.peakMB)
        case let .failed(msg): return "warmup: failed: \(msg)"
        }
    }

    // MARK: - Worker (off the main thread)

    enum WarmupError: Error, CustomStringConvertible {
        case modelsMissing(String)
        case badModel(String)
        case notReady(String)
        var description: String {
            switch self {
            case let .notReady(m): return "warmup not ready (\(m))"
            case let .modelsMissing(m): return "models missing: \(m)"
            case let .badModel(m): return "bad model: \(m)"
            }
        }
    }

    nonisolated static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.ragnus.vp", category: "warmup"
    )

    /// Warmup step weights (sum 1) for the "Warming up… x%" bar, from iPhone17,5 timings: the
    /// encoder CoreML session create dominates (~28 s of ~30 s). Approximate — the bar moves
    /// monotonically through the long step rather than stalling at a step boundary.
    nonisolated static let warmupProgressWeights: [Double] = [
        0.015, // segnet create
        0.04,  // segnet first run
        0.90,  // encoder create (compiled-model cache load + CoreML init)
        0.01,  // encoder first run
        0.005, // vocabulary load
        0.01,  // decoder create
        0.02,  // decoder first run
    ]

    nonisolated static func run(modelsDir: URL?, progress: WarmupProgressHandler? = nil) throws -> WarmedModels {
        let log = Self.log
        let onMain = Thread.isMainThread
        let t0 = DispatchTime.now()
        let startMB = physFootprintMB()
        var peak = startMB
        var timings: [WarmupReport.Session] = []
        var completedWeight = 0.0
        var weightIndex = 0
        func advance() {
            guard weightIndex < Self.warmupProgressWeights.count else { return }
            completedWeight += Self.warmupProgressWeights[weightIndex]
            weightIndex += 1
            progress?(min(completedWeight, 1))
        }
        let dir = try resolveModelsDir(modelsDir)
        log.notice("warmup start: models=\(dir.path, privacy: .public) mainThread=\(onMain) footprint=\(startMB, format: .fixed(precision: 1)) MB")
        let diag = DiagnosticsLog.shared
        diag.record(.info, .warmup, String(format: "warmup start: footprint %.0f MB", startMB),
                    payload: ["kind": "start", "models": dir.lastPathComponent, "main_thread": "\(onMain)"])
        var providers: [String] = []

        func record(_ name: String, _ provider: ORTProvider, _ createMs: Double, _ runMs: Double, cache: EncoderCacheInfo? = nil) {
            let mb = physFootprintMB()
            peak = max(peak, mb)
            timings.append(.init(name: name, provider: "\(provider)", createMs: createMs, firstRunMs: runMs, footprintMB: mb,
                                 coreMLCache: cache?.summary))
            providers.append("\(name)=\(provider)")
            var payload = ["kind": "session", "session": name, "provider": "\(provider)", "create_ms": String(format: "%.1f", createMs),
                           "first_run_ms": String(format: "%.1f", runMs), "footprint_mb": String(format: "%.1f", mb)]
            var msg = String(format: "%@ %@: create %.0f ms, first run %.0f ms, footprint %.0f MB", name, "\(provider)", createMs, runMs, mb)
            if let cache {
                payload.merge(cache.payload) { _, new in new }
                msg += " · coreml cache \(cache.summary)"
            }
            diag.record(.info, .warmup, msg, payload: payload)
            log.notice("\(name, privacy: .public) provider=\(String(describing: provider), privacy: .public) create=\(createMs, format: .fixed(precision: 1)) ms firstRun=\(runMs, format: .fixed(precision: 1)) ms footprint=\(mb, format: .fixed(precision: 1)) MB")
        }

        // SegNet fp16, CoreML EP NeuralNetwork (OMRHomrIOS picks the flags). homr input: `input` [batch, 3, 320, 320].
        let segURL = try modelFile("segnet_", in: dir)
        let (seg, segCreate) = try timed { try SegNetSession.openBackend(modelURL: segURL, provider: .coreML) }
        guard let segIn = seg.inputInfo.first, let segType = segIn.elementType else {
            throw WarmupError.badModel("SegNet has no tensor input")
        }
        let segShape = segIn.shape.enumerated().map { i, d in d >= 0 ? d : (i == 0 ? 1 : (i == 1 ? 3 : 320)) }
        let segBytes = segShape.reduce(1, *) * ORTCSession.byteSize(segType)
        let (_, segRun) = try timed {
            try seg.run(
                inputs: [segIn.name: ORTTensor(type: segType, shape: segShape, data: Data(count: segBytes))],
                outputNames: seg.outputNames
            )
        }
        record("segnet", seg.provider, segCreate, segRun)
        advance() // segnet create
        advance() // segnet first run

        // Encoder fp16, CoreML EP with the app's compiled-model cache (<AppSupport>/coreml-cache/,
        // key = model SHA-256). Zero staff tile (fp32 in, EncoderSession casts to fp16).
        let encURL = try modelFile("encoder_", in: dir)
        var encCache = EncoderCacheInfo()
        let (encPair, encCreate) = try timed { () -> (ORTCSession, EncoderSession) in
            let b = try openCachedEncoder(encURL, info: &encCache)
            return (b, try EncoderSession(backend: b, provider: .coreMLFP16, inputElementType: .float16, modelURL: encURL))
        }
        let (encBackend, encoder) = encPair
        let staffBytes = StaffInputSpec.nchwShape.reduce(1, *) * 4
        let (context, encRun) = try timed {
            try encoder.generateContext(staffImageNormalized: Data(count: staffBytes)).castToFP32ForDecoder()
        }
        record("encoder", .coreML, encCreate, encRun, cache: encCache)
        advance() // encoder create
        advance() // encoder first run

        // Decoder fp32, CPU EP only. One BOS step over the encoder context.
        let decURL = try modelFile("decoder_", in: dir)
        let vocab = try TokenizerLoader.loadVocabulary()
        advance() // vocabulary load
        let (decPair, decCreate) = try timed { () -> (ORTCSession, DecoderSession) in
            let b = try ORTCSession(modelURL: decURL, provider: .cpu)
            return (b, try DecoderSession(vocabulary: vocab, backend: b, provider: .cpu, modelURL: decURL))
        }
        let (decBackend, decoder) = decPair
        let (_, decRun) = try timed {
            try decoder.makeStepRunner(context: context).runStep(
                DecoderStepInput(
                    stepIndex: 0, rhythm: vocab.bosToken, pitch: vocab.nonoteToken, lift: vocab.nonoteToken,
                    articulation: vocab.nonoteToken, slur: vocab.nonoteToken, useFullContext: true,
                    contextDtype: .float32, contextShape: context.shape
                )
            )
        }
        record("decoder", .cpu, decCreate, decRun)
        advance() // decoder create
        advance() // decoder first run

        let totalMs = ms(since: t0)
        let endMB = physFootprintMB()
        peak = max(peak, endMB)
        log.notice("warmup ready: total=\(totalMs, format: .fixed(precision: 1)) ms footprint start=\(startMB, format: .fixed(precision: 1)) end=\(endMB, format: .fixed(precision: 1)) peak=\(peak, format: .fixed(precision: 1)) MB ORT=\(ORTCSession.runtimeVersion, privacy: .public)")
        diag.record(
            .info, .warmup,
            String(format: "warmup ready: total %.0f ms, footprint %.0f → %.0f MB, peak %.0f MB", totalMs, startMB, endMB, peak),
            payload: ["kind": "summary", "total_ms": String(format: "%.1f", totalMs), "start_mb": String(format: "%.1f", startMB),
                      "end_mb": String(format: "%.1f", endMB), "peak_mb": String(format: "%.1f", peak),
                      "providers": providers.joined(separator: " "), "ort": ORTCSession.runtimeVersion]
        )
        let report = WarmupReport(
            sessions: timings, totalMs: totalMs, startMB: startMB, endMB: endMB, peakMB: peak,
            ranOnMainThread: onMain, modelsDir: dir
        )
        return WarmedModels(
            segnet: seg, encoderBackend: encBackend, decoderBackend: decBackend,
            encoder: encoder, decoder: decoder, vocabulary: vocab, report: report
        )
    }

    /// How the encoder session used the CoreML cache (warmup diagnostics).
    struct EncoderCacheInfo: Sendable {
        /// hit / miss / incomplete (half entry deleted, cold compile) / off / failed.
        var state = "off"
        var key: String?
        var keyMs: Double = 0
        var modelMB: Double = 0
        var directory: String?
        var error: String?
        var removedStale: [String] = []

        var summary: String {
            var s = state
            if let key { s += " key \(key.prefix(12))" }
            if modelMB > 0 { s += String(format: " model %.0f MB", modelMB) }
            if keyMs > 0 { s += String(format: " key_ms %.0f", keyMs) }
            if let error { s += " (\(error))" }
            return s
        }

        var payload: [String: String] {
            var p = ["coreml_cache": state, "coreml_cache_used": state == "hit" ? "1" : "0",
                     "coreml_cache_key_ms": String(format: "%.1f", keyMs)]
            if modelMB > 0 { p["coreml_cache_model_mb"] = String(format: "%.1f", modelMB) }
            if let key { p["coreml_cache_key"] = key }
            if let directory { p["coreml_cache_dir"] = directory }
            if let error { p["coreml_cache_error"] = error }
            if !removedStale.isEmpty { p["coreml_cache_removed"] = removedStale.joined(separator: " ") }
            return p
        }
    }

    /// `OMR_COREML_CACHE=0` disables the cache (plain CoreML EP, compiled into a temp dir every launch).
    nonisolated static var coreMLCacheEnabled: Bool {
        ProcessInfo.processInfo.environment["OMR_COREML_CACHE"] != "0"
    }

    /// Encoder `.coreML` session through `CoreMLCacheStore`. A failed create on a cached entry deletes it and
    /// retries uncached, so a bad entry can never break the warmup. Never used for the decoder.
    nonisolated static func openCachedEncoder(_ url: URL, info: inout EncoderCacheInfo, root: URL? = nil) throws -> ORTCSession {
        guard coreMLCacheEnabled else { return try ORTCSession(modelURL: url, provider: .coreML) }
        let store: CoreMLCacheStore
        let key: String
        do {
            store = try CoreMLCacheStore.prepare(root: root)
            let (k, ms) = try timed { try CoreMLModelCache.sha256Hex(ofFileAt: url) }
            key = k
            info.key = k
            info.keyMs = ms
            let modelBytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.doubleValue ?? 0
            info.modelMB = modelBytes / 1_048_576
            info.directory = store.root.path
            info.removedStale = store.removeStale(keeping: [k])
        } catch {
            info.state = "failed"
            info.error = "cache dir: \(error)"
            return try ORTCSession(modelURL: url, provider: .coreML)
        }
        info.state = store.prepareEntry(key).rawValue
        do {
            let s = try ORTCSession(modelURL: url, provider: .coreML, cacheDirectory: store.root, cacheKey: key)
            store.markComplete(key)
            return s
        } catch {
            store.remove(key)
            info.state = "failed"
            info.error = "\(error)"
            return try ORTCSession(modelURL: url, provider: .coreML)
        }
    }

    nonisolated static func resolveModelsDir(_ explicit: URL?) throws -> URL {
        if let explicit { return explicit }
        if let env = ProcessInfo.processInfo.environment["OMR_MODELS_DIR"], !env.isEmpty {
            return URL(fileURLWithPath: env, isDirectory: true)
        }
        if let bundled = Bundle.main.url(forResource: "models", withExtension: nil) { return bundled }
        throw WarmupError.modelsMissing("no models/ in the app bundle and OMR_MODELS_DIR unset")
    }

    nonisolated static func modelFile(_ prefix: String, in dir: URL) throws -> URL {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        guard let name = names.filter({ $0.hasPrefix(prefix) && $0.hasSuffix(".onnx") }).sorted().first else {
            throw WarmupError.modelsMissing("\(prefix)*.onnx not in \(dir.path)")
        }
        return dir.appendingPathComponent(name)
    }

    nonisolated static func timed<T>(_ body: () throws -> T) rethrows -> (T, Double) {
        let t = DispatchTime.now()
        let v = try body()
        return (v, ms(since: t))
    }

    nonisolated static func ms(since t: DispatchTime) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - t.uptimeNanoseconds) / 1_000_000
    }

    /// `task_info(TASK_VM_INFO).phys_footprint` in MB (what Xcode / jetsam count); -1 on error.
    nonisolated static func physFootprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }
}

struct WarmupReport: Sendable {
    struct Session: Sendable {
        var name: String
        var provider: String
        var createMs: Double
        var firstRunMs: Double
        var footprintMB: Double
        /// CoreML compiled-model cache use (encoder only), e.g. "hit key 1a2b3c4d5e6f"; nil = no cache.
        var coreMLCache: String? = nil
    }

    var sessions: [Session]
    var totalMs: Double
    var startMB: Double
    var endMB: Double
    var peakMB: Double
    var ranOnMainThread: Bool
    var modelsDir: URL

    var lines: [String] {
        sessions.map {
            String(format: "%@ %@: create %.0f ms, first run %.0f ms, %.0f MB",
                   $0.name, $0.provider, $0.createMs, $0.firstRunMs, $0.footprintMB)
                + ($0.coreMLCache.map { ", coreml cache \($0)" } ?? "")
        } + [String(format: "total %.0f ms, footprint %.0f → %.0f MB, peak %.0f MB", totalMs, startMB, endMB, peakMB)]
    }
}

/// Sessions created by the warmup (ORT sessions are not thread-confined; used serially).
final class WarmedModels: @unchecked Sendable {
    let segnet: ORTCSession
    /// Encoder fp16 on the CoreML EP (`.coreML`), decoder fp32 on the CPU EP (`.cpu`).
    let encoderBackend: ORTCSession
    let decoderBackend: ORTCSession
    let encoder: EncoderSession
    let decoder: DecoderSession
    let vocabulary: HomrVocabulary
    let report: WarmupReport

    init(
        segnet: ORTCSession, encoderBackend: ORTCSession, decoderBackend: ORTCSession,
        encoder: EncoderSession, decoder: DecoderSession, vocabulary: HomrVocabulary, report: WarmupReport
    ) {
        self.segnet = segnet
        self.encoderBackend = encoderBackend
        self.decoderBackend = decoderBackend
        self.encoder = encoder
        self.decoder = decoder
        self.vocabulary = vocabulary
        self.report = report
    }
}
