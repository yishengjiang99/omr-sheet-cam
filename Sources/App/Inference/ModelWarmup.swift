import Darwin
import Foundation
import OMRHomrIOS
import os

/// Launch-time background warmup of the three pinned homr models (models.lock), bundled into
/// `<App>.app/models/` by the "Bundle ONNX models" build phase.
///
/// - SegNet fp16 + Encoder fp16: `ORTCSession(provider: .coreML)` (CoreML EP, CPU EP fallback).
/// - Decoder fp32: `ORTCSession(provider: .cpu)` (locked rule; `DecoderSession` enforces it).
/// - One cheap dummy inference each: SegNet zeros `[1,3,320,320]`, Encoder zeros staff tile
///   `[1,1,256,1280]`, Decoder one step (BOS) over that encoder context.
/// - All ORT / CoreML work runs in a detached task, never on the main thread. State is published
///   on the main actor for the debug UI.
/// - Logs (`Logger`, subsystem = bundle id, category `warmup`): per-session create / first-run ms
///   and provider, `phys_footprint` MB after each session, total ms and peak MB.
///
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
    /// Warm sessions, kept alive for the parse path once it lands.
    private(set) var models: WarmedModels?
    private var task: Task<WarmupReport?, Never>?

    init() {}

    /// Starts the warmup once (re-runs only after a failure). Returns immediately; await the task
    /// value for the report. Never blocks the caller.
    @discardableResult
    func start(modelsDir: URL? = nil) -> Task<WarmupReport?, Never> {
        if let task, state != .idle, !isFailed { return task }
        state = .warming
        report = nil
        let worker = Task.detached(priority: .utility) { () -> Result<WarmedModels, Error> in
            Result { try ModelWarmup.run(modelsDir: modelsDir) }
        }
        let t = Task { [weak self] () -> WarmupReport? in
            let result = await worker.value
            guard let self else { return try? result.get().report }
            switch result {
            case let .success(m):
                self.models = m
                self.report = m.report
                self.state = .ready
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
        if let models, state == .ready { return models }
        _ = await start(modelsDir: modelsDir).value
        if let models, state == .ready { return models }
        throw WarmupError.notReady(debugLine)
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

    nonisolated static func run(modelsDir: URL?) throws -> WarmedModels {
        let log = Self.log
        let onMain = Thread.isMainThread
        let t0 = DispatchTime.now()
        let startMB = physFootprintMB()
        var peak = startMB
        var timings: [WarmupReport.Session] = []
        let dir = try resolveModelsDir(modelsDir)
        log.notice("warmup start: models=\(dir.path, privacy: .public) mainThread=\(onMain) footprint=\(startMB, format: .fixed(precision: 1)) MB")
        let diag = DiagnosticsLog.shared
        diag.record(.info, .warmup, String(format: "warmup start: footprint %.0f MB", startMB),
                    payload: ["kind": "start", "models": dir.lastPathComponent, "main_thread": "\(onMain)"])
        var providers: [String] = []

        func record(_ name: String, _ provider: ORTProvider, _ createMs: Double, _ runMs: Double) {
            let mb = physFootprintMB()
            peak = max(peak, mb)
            timings.append(.init(name: name, provider: "\(provider)", createMs: createMs, firstRunMs: runMs, footprintMB: mb))
            providers.append("\(name)=\(provider)")
            diag.record(
                .info, .warmup,
                String(format: "%@ %@: create %.0f ms, first run %.0f ms, footprint %.0f MB", name, "\(provider)", createMs, runMs, mb),
                payload: ["kind": "session", "session": name, "provider": "\(provider)", "create_ms": String(format: "%.1f", createMs),
                          "first_run_ms": String(format: "%.1f", runMs), "footprint_mb": String(format: "%.1f", mb)]
            )
            log.notice("\(name, privacy: .public) provider=\(String(describing: provider), privacy: .public) create=\(createMs, format: .fixed(precision: 1)) ms firstRun=\(runMs, format: .fixed(precision: 1)) ms footprint=\(mb, format: .fixed(precision: 1)) MB")
        }

        // SegNet fp16, CoreML EP. homr input: `input` [batch, 3, 320, 320].
        let segURL = try modelFile("segnet_", in: dir)
        let (seg, segCreate) = try timed { try ORTCSession(modelURL: segURL, provider: .coreML) }
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

        // Encoder fp16, CoreML EP. Zero staff tile (fp32 in, EncoderSession casts to fp16).
        let encURL = try modelFile("encoder_", in: dir)
        let (encPair, encCreate) = try timed { () -> (ORTCSession, EncoderSession) in
            let b = try ORTCSession(modelURL: encURL, provider: .coreML)
            return (b, try EncoderSession(backend: b, provider: .coreMLFP16, inputElementType: .float16, modelURL: encURL))
        }
        let (encBackend, encoder) = encPair
        let staffBytes = StaffInputSpec.nchwShape.reduce(1, *) * 4
        let (context, encRun) = try timed {
            try encoder.generateContext(staffImageNormalized: Data(count: staffBytes)).castToFP32ForDecoder()
        }
        record("encoder", .coreML, encCreate, encRun)

        // Decoder fp32, CPU EP only. One BOS step over the encoder context.
        let decURL = try modelFile("decoder_", in: dir)
        let vocab = try TokenizerLoader.loadVocabulary()
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
