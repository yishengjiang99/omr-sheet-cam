import Foundation
import XCTest
import OMRHomrIOS

/// Gate 1 on iOS / macOS: `fixtures/oracle.c_scale_staff/staff.npy` → `decodeStaff(tensor:)` over
/// `ORTCSession` (ORT C API; encoder `.coreML` = CoreML EP + CPU fallback, or `.cpu`; decoder fp32
/// `.cpu` only) must equal `expected.tokens.json` on all six fields. Mirrors the package's Linux
/// `Gate1ORTCTests`.
///
/// Env: `OMR_MODELS_DIR` (default `<repo>/models`, from `scripts/fetch-models`),
/// `OMR_ENCODER_PROVIDER` = `coreml` (default) | `cpu`. Under xcodebuild pass them as
/// `TEST_RUNNER_OMR_MODELS_DIR` / `TEST_RUNNER_OMR_ENCODER_PROVIDER`.
/// Skips only when the pinned models are absent (e.g. a device without files).
final class Gate1StaffTokenMatchTests: XCTestCase {

    func testCScaleOracleTokenMatch() throws {
        try Self.runGate1(encoderProvider: Self.encoderProvider())
    }

    // MARK: - Gate 1

    /// `<repo>` = parent of `Tests/`. Valid wherever the checkout is readable (Mac, simulator).
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // Tests/
        .deletingLastPathComponent() // repo root

    struct ConfigError: Error, CustomStringConvertible {
        var description: String
    }

    /// `OMR_ENCODER_PROVIDER`: `coreml` (default) | `cpu`. Decoder is always `.cpu`.
    static func encoderProvider(
        _ env: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> ORTProvider {
        switch env["OMR_ENCODER_PROVIDER"]?.lowercased() ?? "coreml" {
        case "coreml": return .coreML
        case "cpu": return .cpu
        case let other: throw ConfigError(description: "OMR_ENCODER_PROVIDER must be coreml|cpu, got '\(other)'")
        }
    }

    static func runGate1(
        encoderProvider: ORTProvider,
        repoRoot: URL = Gate1StaffTokenMatchTests.repoRoot,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) throws {
        let fm = FileManager.default
        let dir = repoRoot.appendingPathComponent("fixtures/oracle.c_scale_staff")
        let npy = dir.appendingPathComponent("staff.npy")
        let json = dir.appendingPathComponent("expected.tokens.json")
        guard fm.fileExists(atPath: npy.path), fm.fileExists(atPath: json.path) else {
            throw ConfigError(description: "Gate-1 fixtures missing: \(npy.path) / expected.tokens.json")
        }
        let models = try modelURLs(repoRoot: repoRoot, env: env)

        let expected = try loadExpectedSymbols(from: json)
        XCTAssertFalse(expected.isEmpty, "expected.tokens.json has no symbols")
        let tensor = try StaffTensor.loadNPY(npy)
        let session = try StaffInferenceSession(
            encoder: ORTCSession(modelURL: models.encoder, provider: encoderProvider),
            decoder: ORTCSession(modelURL: models.decoder, provider: .cpu),
            vocabulary: TokenizerLoader.loadVocabulary()
        )
        let got = try session.decodeStaff(tensor: tensor)

        var note = ""
        if let idx = firstMismatch(got, expected) {
            if encoderProvider == .coreML {
                note = cpuEncoderDiagnostics(
                    session: session, encoderModel: models.encoder,
                    tensor: tensor, expected: expected, coreMLDivergence: idx
                )
            } else {
                note = "Gate-1 CPU mismatch: decode first diverges @\(idx)"
            }
            print(note)
        } else {
            print(
                "Gate-1 PASS: \(got.count)/\(expected.count) symbols match oracle "
                    + "(ORT \(ORTCSession.runtimeVersion), encoder \(encoderProvider), decoder cpu)"
            )
        }
        assertSymbolsEqual(got, expected, note: note)
    }

    /// Mismatch under CoreML: re-run the encoder on `.cpu`, diff fp32 contexts, decode the CPU
    /// context. Never throws; the caller still fails on the CoreML mismatch.
    static func cpuEncoderDiagnostics(
        session: StaffInferenceSession,
        encoderModel: URL,
        tensor: StaffTensor,
        expected: [EncodedSymbol],
        coreMLDivergence: Int
    ) -> String {
        let head = "Gate-1 CoreML mismatch: CoreML decode first diverges @\(coreMLDivergence)"
        do {
            let input = tensor.float32LEData
            let cpuEncoder = try EncoderSession(
                backend: ORTCSession(modelURL: encoderModel, provider: .cpu),
                provider: .cpuFallback,
                inputElementType: .float16,
                modelURL: encoderModel
            )
            let coreMLCtx = try session.encoder.generateContext(staffImageNormalized: input).castToFP32ForDecoder()
            let cpuCtx = try cpuEncoder.generateContext(staffImageNormalized: input).castToFP32ForDecoder()
            let diff = maxAbsDiff(fp32LE: coreMLCtx.bytes, cpuCtx.bytes)
            let cpuGot = try session.decoderLoop.generate(
                context: cpuCtx, stepRunner: session.decoder.makeStepRunner(context: cpuCtx)
            )
            let cpuVerdict = firstMismatch(cpuGot, expected).map { "no (diverges @\($0))" } ?? "yes"
            return "\(head); encoder context max|coreML-cpu| (fp32) = \(diff) "
                + "(shapes \(coreMLCtx.shape) vs \(cpuCtx.shape)); CPU-encoder decode matches oracle: \(cpuVerdict)"
        } catch {
            return "\(head); CPU-encoder diagnostics failed: \(error)"
        }
    }

    // MARK: - Models / fixtures

    /// `<OMR_MODELS_DIR | repo/models>/<models.lock encoder_*, decoder_*>`; skips if absent.
    static func modelURLs(repoRoot: URL, env: [String: String]) throws -> (encoder: URL, decoder: URL) {
        let dir = env["OMR_MODELS_DIR"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
            ?? repoRoot.appendingPathComponent("models")
        let names = pinnedModelNames(lock: repoRoot.appendingPathComponent("models.lock"))
        let enc = dir.appendingPathComponent(names.encoder)
        let dec = dir.appendingPathComponent(names.decoder)
        let missing = [enc, dec].filter { !FileManager.default.fileExists(atPath: $0.path) }
        guard missing.isEmpty else {
            throw XCTSkip(
                "pinned models missing (\(missing.map(\.lastPathComponent))) in \(dir.path); "
                    + "run scripts/fetch-models or set OMR_MODELS_DIR"
            )
        }
        return (enc, dec)
    }

    /// Filenames from `models.lock` (`<sha256>  <filename>  <url>`); pinned fallback if unreadable.
    static func pinnedModelNames(lock: URL) -> (encoder: String, decoder: String) {
        let stem = "pytorch_model_465-597144cab54c8f6d0f6c9619df5c5312694eadd6"
        var encoder = "encoder_\(stem)_fp16.onnx"
        var decoder = "decoder_\(stem).onnx"
        guard let text = try? String(contentsOf: lock, encoding: .utf8) else { return (encoder, decoder) }
        let files = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .compactMap { $0.split(whereSeparator: \.isWhitespace).dropFirst().first.map(String.init) }
        if let e = files.first(where: { $0.hasPrefix("encoder_") }) { encoder = e }
        if let d = files.first(where: { $0.hasPrefix("decoder_") }) { decoder = d }
        return (encoder, decoder)
    }

    private struct ExpectedTokensFile: Decodable {
        var symbols: [OracleSymbolFields]
    }

    static func loadExpectedSymbols(from url: URL) throws -> [EncodedSymbol] {
        try JSONDecoder().decode(ExpectedTokensFile.self, from: Data(contentsOf: url))
            .symbols.map { EncodedSymbol(oracleFields: $0) }
    }

    // MARK: - Compare

    static func firstMismatch(_ got: [EncodedSymbol], _ expected: [EncodedSymbol]) -> Int? {
        let n = min(got.count, expected.count)
        if let i = (0..<n).first(where: { got[$0].oracleFields != expected[$0].oracleFields }) { return i }
        return got.count == expected.count ? nil : n
    }

    static func maxAbsDiff(fp32LE a: Data, _ b: Data) -> Float {
        guard a.count == b.count, a.count % 4 == 0 else { return .infinity }
        func floats(_ d: Data) -> [Float] {
            d.withUnsafeBytes { raw in
                (0..<(d.count / 4)).map {
                    Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: $0 * 4, as: UInt32.self)))
                }
            }
        }
        return zip(floats(a), floats(b)).reduce(0) { max($0, abs($1.0 - $1.1)) }
    }

    static func assertSymbolsEqual(
        _ got: [EncodedSymbol],
        _ expected: [EncodedSymbol],
        note: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let ctx = note.isEmpty ? "" : " | \(note)"
        XCTAssertEqual(got.count, expected.count, "symbol count\(ctx)", file: file, line: line)
        for i in 0..<min(got.count, expected.count) {
            XCTAssertEqual(got[i].rhythm, expected[i].rhythm, "rhythm @\(i)\(ctx)", file: file, line: line)
            XCTAssertEqual(got[i].pitch, expected[i].pitch, "pitch @\(i)\(ctx)", file: file, line: line)
            XCTAssertEqual(got[i].lift, expected[i].lift, "lift @\(i)\(ctx)", file: file, line: line)
            XCTAssertEqual(got[i].articulation, expected[i].articulation, "articulation @\(i)\(ctx)", file: file, line: line)
            XCTAssertEqual(got[i].slur, expected[i].slur, "slur @\(i)\(ctx)", file: file, line: line)
            XCTAssertEqual(got[i].position, expected[i].position, "position @\(i)\(ctx)", file: file, line: line)
        }
    }
}
