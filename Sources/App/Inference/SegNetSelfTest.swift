import Foundation
import OMRHomrIOS
import SwiftUI

/// Settings → Developer → "SegNet self-test": the bundled C-scale oracle page (`selftest/c_major_scale_page.png`
/// = `fixtures/mono.c_major_scale/input.png`, the ios-sim page test's image) → ImageIO gray8 →
/// `PagePipeline.preprocess` → SegNet three ways → per-class pixel counts, raw output min / max / NaN,
/// create + run ms, and `PagePipeline.detectStaffs`. Runs off the main thread; writes one
/// `recognition` / `segnet_selftest` event (shown in "Copy as prompt").
///
/// Variants, built only through OMRHomrIOS's public API:
/// - `mlProgram`: `ORTCSession(modelURL:provider: .coreML)` (legacy flags MLProgram | CPUAndGPU).
/// - `neuralNetwork`: production path: `SegNetSession.openBackend(modelURL:provider: .coreML)` (CoreML EP
///   NeuralNetwork, legacy flags 0x000), the same call `ModelWarmup` uses.
/// - `cpu`: `ORTCSession(modelURL:provider: .cpu)`, diagnostic reference only (recognition never uses it).
enum SegNetSelfTest {
    enum Variant: String, CaseIterable, Sendable {
        case mlProgram = "mlprogram"
        case neuralNetwork = "neuralnetwork"
        case cpu

        var title: String {
            switch self {
            case .mlProgram: return "CoreML EP · MLProgram"
            case .neuralNetwork: return "CoreML EP · NeuralNetwork (production path)"
            case .cpu: return "CPU EP (diagnostic only)"
            }
        }
    }

    /// homr 7d97c3c on the C-scale page (`fixtures/oracle.pages/mono.c_major_scale/stages.json`), classes 0…5.
    static let homrClassCounts = [5_197_875, 1240, 2056, 1373, 10256, 0]

    struct Stats: Sendable, Equatable {
        var min = Float.infinity
        var max = -Float.infinity
        var nan = 0
        var inf = 0
        var count = 0
    }

    struct VariantResult: Sendable, Identifiable {
        var variant: Variant
        var id: String { variant.rawValue }
        /// nil = ran; else why it could not be built ("unavailable: …") or failed.
        var unavailable: String?
        var error: String?
        var createMs: Double = 0
        var runMs: Double = 0
        var classCounts: [Int] = []
        var stats = Stats()
        /// Staffs found by `PagePipeline.detectStaffs`, or nil with `detectError`.
        var staffCount: Int?
        var detectError: String?

        var l1VsHomr: Int? {
            guard classCounts.count == SegNetSelfTest.homrClassCounts.count else { return nil }
            return zip(classCounts, SegNetSelfTest.homrClassCounts).map { abs($0 - $1) }.reduce(0, +)
        }

        var passed: Bool { unavailable == nil && error == nil && (staffCount ?? 0) > 0 && stats.nan == 0 }

        var line: String {
            if let unavailable { return unavailable }
            if let error { return String(format: "FAILED after create %.0f ms: %@", createMs, error) }
            let staffs = staffCount.map { "\($0) staff\($0 == 1 ? "" : "s")" } ?? "no staff (\(detectError ?? "?"))"
            return String(format: "classes %@ · L1 vs homr %@ · min %.3f max %.3f nan %d inf %d · create %.0f ms, run %.0f ms · %@",
                          "\(classCounts)", l1VsHomr.map(String.init) ?? "?", stats.min, stats.max, stats.nan, stats.inf,
                          createMs, runMs, staffs)
        }
    }

    struct Report: Sendable {
        var page: String
        var results: [VariantResult]
        var totalMs: Double
        var error: String?
    }

    enum SelfTestError: Error, CustomStringConvertible {
        case pageMissing(String)
        var description: String {
            switch self { case let .pageMissing(m): return "self-test page missing: \(m)" }
        }
    }

    /// `<App>.app/selftest/c_major_scale_page.png` (copied by the "Bundle Gate-1 fixtures" build phase).
    static func bundledPage(_ bundle: Bundle = .main) throws -> URL {
        guard let url = bundle.url(forResource: "c_major_scale_page", withExtension: "png", subdirectory: "selftest") else {
            throw SelfTestError.pageMissing("no selftest/c_major_scale_page.png in \(bundle.bundlePath)")
        }
        return url
    }

    enum Build {
        case session(ORTCSession)
        case unavailable(String)
    }

    /// Public-API session per variant (see the type doc).
    static func build(_ v: Variant, model: URL) throws -> Build {
        switch v {
        case .mlProgram:
            return .session(try ORTCSession(modelURL: model, provider: .coreML))
        case .neuralNetwork:
            // Same call as ModelWarmup: CoreML EP NeuralNetwork, legacy flags 0x000 (OMRHomrIOS picks them).
            return .session(try SegNetSession.openBackend(modelURL: model, provider: .coreML))
        case .cpu:
            return .session(try ORTCSession(modelURL: model, provider: .cpu))
        }
    }

    /// Heavy: call from a detached task (never the main thread).
    static func run(modelsDir: URL? = nil, page: URL? = nil, variants: [Variant] = Variant.allCases,
                    log: DiagnosticsLog = .shared) -> Report {
        let t0 = DispatchTime.now()
        var report = Report(page: "?", results: [], totalMs: 0)
        do {
            let pageURL = try page ?? bundledPage()
            let model = try ModelWarmup.modelFile("segnet_", in: ModelWarmup.resolveModelsDir(modelsDir))
            let g = try Gray8Image.decode(imageData: Data(contentsOf: pageURL))
            let pre = try PagePipeline.preprocess(gray8: g.pixels, width: g.width, height: g.height)
            report.page = "\(pageURL.lastPathComponent) \(g.width)x\(g.height) → \(pre.width)x\(pre.height)"
            for v in variants {
                report.results.append(runVariant(v, model: model, page: pre))
            }
        } catch {
            report.error = String(describing: error)
        }
        report.totalMs = ModelWarmup.ms(since: t0)
        record(report, log: log)
        return report
    }

    static func runVariant(_ v: Variant, model: URL, page: PagePipeline.PreprocessedPage) -> VariantResult {
        var r = VariantResult(variant: v)
        let tc = DispatchTime.now()
        let session: ORTCSession
        do {
            switch try build(v, model: model) {
            case let .unavailable(reason):
                r.unavailable = reason
                return r
            case let .session(s):
                session = s
            }
        } catch {
            r.createMs = ModelWarmup.ms(since: tc)
            r.error = "create: \(error)"
            return r
        }
        r.createMs = ModelWarmup.ms(since: tc)
        let probe = StatsBackend(session)
        let tr = DispatchTime.now()
        do {
            let map = try PagePipeline.segment(page, segnet: SegNetSession(backend: probe))
            r.runMs = ModelWarmup.ms(since: tr)
            var counts = [Int](repeating: 0, count: SegNetSession.classCount)
            for c in map where Int(c) < counts.count { counts[Int(c)] += 1 }
            r.classCounts = counts
            r.stats = probe.stats
            do {
                r.staffCount = try PagePipeline.detectStaffs(segmentation: map, width: page.width, height: page.height).staffs.count
            } catch {
                r.detectError = String(describing: error)
            }
        } catch {
            r.runMs = ModelWarmup.ms(since: tr)
            r.stats = probe.stats
            r.error = "run: \(error)"
        }
        return r
    }

    static func record(_ report: Report, log: DiagnosticsLog) {
        var p: [String: String] = ["kind": "segnet_selftest", "page": report.page, "total_ms": String(format: "%.1f", report.totalMs),
                                   "ort": ORTCSession.runtimeVersion]
        for r in report.results { p[r.variant.rawValue] = r.line }
        if let e = report.error { p["error"] = e }
        let summary = report.results.map { r -> String in
            let state = r.unavailable != nil ? "unavailable" : (r.passed ? "ok" : "FAIL")
            return "\(r.variant.rawValue) \(state)"
        }.joined(separator: ", ")
        let failed = report.error != nil || report.results.contains { $0.unavailable == nil && !$0.passed }
        let msg = String(format: "SegNet self-test %.0f ms: %@", report.totalMs, report.error.map { "error \($0)" } ?? summary)
        log.record(failed ? .warn : .info, .recognition, msg, payload: p)
    }

    /// fp16 bits → Float for every 16-bit pattern (output stats).
    static let floatOfHalf: [Float] = (0..<65536).map { halfToFloat(UInt16($0)) }

    static func halfToFloat(_ h: UInt16) -> Float {
        let sign = UInt32(h & 0x8000) << 16
        let exp = UInt32(h & 0x7C00) >> 10
        var mant = UInt32(h & 0x03FF)
        let bits: UInt32
        if exp == 0 {
            if mant == 0 {
                bits = sign
            } else { // subnormal
                var e: UInt32 = 127 - 15 + 1
                while mant & 0x400 == 0 { mant <<= 1; e -= 1 }
                bits = sign | (e << 23) | ((mant & 0x3FF) << 13)
            }
        } else if exp == 0x1F {
            bits = sign | 0x7F80_0000 | (mant << 13)
        } else {
            bits = sign | ((exp + 127 - 15) << 23) | (mant << 13)
        }
        return Float(bitPattern: bits)
    }
}

/// Forwards to an ORT session and accumulates min / max / NaN / Inf over every `output` tensor.
final class StatsBackend: ORTSessionBackend, @unchecked Sendable {
    let inner: ORTCSession
    private(set) var stats = SegNetSelfTest.Stats()

    init(_ inner: ORTCSession) { self.inner = inner }

    required init(modelURL: URL, provider: ORTProvider) throws {
        inner = try ORTCSession(modelURL: modelURL, provider: provider)
    }

    var inputNames: [String] { inner.inputNames }
    var outputNames: [String] { inner.outputNames }

    func run(inputs: [String: ORTTensor], outputNames: [String]) throws -> [String: ORTTensor] {
        let out = try inner.run(inputs: inputs, outputNames: outputNames)
        for t in out.values { accumulate(t) }
        return out
    }

    private func accumulate(_ t: ORTTensor) {
        var s = stats
        func add(_ x: Float) {
            if x.isNaN { s.nan += 1; return }
            if x.isInfinite { s.inf += 1; return }
            if x < s.min { s.min = x }
            if x > s.max { s.max = x }
            s.count += 1
        }
        t.data.withUnsafeBytes { raw in
            switch t.type {
            case .float16:
                SegNetSelfTest.floatOfHalf.withUnsafeBufferPointer { f in
                    for b in raw.bindMemory(to: UInt16.self) { add(f[Int(UInt16(littleEndian: b))]) }
                }
            case .float32:
                for b in raw.bindMemory(to: UInt32.self) { add(Float(bitPattern: UInt32(littleEndian: b))) }
            default:
                break
            }
        }
        stats = s
    }
}

@MainActor
final class SegNetSelfTestModel: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var report: SegNetSelfTest.Report?

    func run() {
        guard !running else { return }
        running = true
        Task {
            let r = await Task.detached(priority: .userInitiated) { SegNetSelfTest.run() }.value
            report = r
            running = false
        }
    }
}

struct SegNetSelfTestScreen: View {
    @StateObject private var model = SegNetSelfTestModel()

    var body: some View {
        List {
            Section {
                Button {
                    model.run()
                } label: {
                    HStack {
                        Label(model.running ? "Running…" : "Run SegNet self-test", systemImage: "play.circle")
                        if model.running { Spacer(); ProgressView() }
                    }
                }
                .disabled(model.running)
                .accessibilityIdentifier("selftest.segnet.run")
            } footer: {
                Text("C-scale oracle page through SegNet on the CoreML EP (MLProgram, NeuralNetwork) and the CPU EP. homr: classes \(SegNetSelfTest.homrClassCounts.description), 1 staff.")
            }
            if let r = model.report {
                Section("Page") {
                    Text(r.page).font(.caption.monospaced())
                    Text(String(format: "total %.0f ms · ORT %@", r.totalMs, ORTCSession.runtimeVersion)).font(.caption.monospaced())
                    if let e = r.error { Text(e).font(.caption.monospaced()).foregroundStyle(.red) }
                }
                ForEach(r.results) { v in
                    Section(v.variant.title) {
                        Label(v.unavailable != nil ? "Unavailable" : (v.passed ? "Staff found" : "Failed"),
                              systemImage: v.unavailable != nil ? "minus.circle" : (v.passed ? "checkmark.circle.fill" : "xmark.octagon.fill"))
                            .foregroundStyle(v.unavailable != nil ? Color.secondary : (v.passed ? Color.green : Color.red))
                        Text(v.line).font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
            }
        }
        .navigationTitle("SegNet self-test")
        .navigationBarTitleDisplayMode(.inline)
    }
}
