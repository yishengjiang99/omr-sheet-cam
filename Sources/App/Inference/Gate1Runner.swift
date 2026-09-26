import Foundation
import OMRHomrIOS
import os

/// Gate-1 oracle comparison shared by the app runner and `Gate1StaffTokenMatchTests`.
enum Gate1Oracle {
    private struct ExpectedTokensFile: Decodable {
        var symbols: [OracleSymbolFields]
    }

    /// `expected.tokens.json` (homr `Staff2Score.predict`, EOS excluded) → symbols.
    static func loadExpectedSymbols(from url: URL) throws -> [EncodedSymbol] {
        try JSONDecoder().decode(ExpectedTokensFile.self, from: Data(contentsOf: url))
            .symbols.map { EncodedSymbol(oracleFields: $0) }
    }

    /// First index whose six oracle fields differ, or where one sequence ends early; nil = match.
    static func firstMismatch(_ got: [EncodedSymbol], _ expected: [EncodedSymbol]) -> Int? {
        let n = min(got.count, expected.count)
        if let i = (0..<n).first(where: { got[$0].oracleFields != expected[$0].oracleFields }) { return i }
        return got.count == expected.count ? nil : n
    }

    /// Expected positions whose six fields match exactly.
    static func matchedCount(_ got: [EncodedSymbol], _ expected: [EncodedSymbol]) -> Int {
        zip(got, expected).filter { $0.oracleFields == $1.oracleFields }.count
    }

    /// max |a - b| over little-endian fp32 buffers; +inf if sizes differ.
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
}

struct Gate1Result: Sendable {
    var input: String
    var matched: Int
    var expectedCount: Int
    var gotCount: Int
    /// (index, got, expected) of the first divergence; nil on PASS.
    var divergence: (index: Int, got: String, expected: String)?
    var decodeMs: Double
    var encoderProvider: String
    var ortVersion: String

    var passed: Bool { divergence == nil }

    /// `PASS 12/12` or `FAIL n/12, first divergence at i: got X expected Y`.
    var verdict: String {
        guard let d = divergence else { return "PASS \(matched)/\(expectedCount)" }
        return "FAIL \(matched)/\(expectedCount), first divergence at \(d.index): got \(d.got) expected \(d.expected)"
    }

    var detail: String {
        String(format: "decode %.0f ms, encoder %@, ORT %@", decodeMs, encoderProvider, ortVersion)
    }
}

/// In-app Gate 1 (TestFlight / physical iPhone): bundled `gate1/staff.npy` → the package's
/// `StaffInferenceSession(encoder:decoder:vocabulary:).decodeStaff(tensor:)` over the warmed
/// `ORTCSession`s (encoder CoreML EP, decoder CPU) → compare with `gate1/expected.tokens.json`.
/// Synchronous; call off the main thread.
enum Gate1Runner {
    enum RunnerError: Error, CustomStringConvertible {
        case fixturesMissing(String)
        var description: String {
            switch self { case let .fixturesMissing(m): return "Gate-1 fixtures missing: \(m)" }
        }
    }

    static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.ragnus.vp", category: "gate1")

    /// `<App>.app/gate1/` (copied from fixtures/oracle.c_scale_staff by the "Bundle Gate-1 fixtures" phase).
    static func bundledFixturesDir(_ bundle: Bundle = .main) throws -> URL {
        guard let dir = bundle.url(forResource: "gate1", withExtension: nil) else {
            throw RunnerError.fixturesMissing("no gate1/ in \(bundle.bundlePath)")
        }
        return dir
    }

    static func runNPY(models: WarmedModels, fixturesDir: URL? = nil) throws -> Gate1Result {
        let dir = try fixturesDir ?? bundledFixturesDir()
        let npy = dir.appendingPathComponent("staff.npy")
        let json = dir.appendingPathComponent("expected.tokens.json")
        for f in [npy, json] where !FileManager.default.fileExists(atPath: f.path) {
            throw RunnerError.fixturesMissing(f.path)
        }
        let expected = try Gate1Oracle.loadExpectedSymbols(from: json)
        let tensor = try StaffTensor.loadNPY(npy)
        return try decode(tensor: tensor, input: "npy", expected: expected, models: models)
    }

    static func decode(
        tensor: StaffTensor, input: String, expected: [EncodedSymbol], models: WarmedModels
    ) throws -> Gate1Result {
        let session = try StaffInferenceSession(
            encoder: models.encoderBackend, decoder: models.decoderBackend, vocabulary: models.vocabulary
        )
        let t0 = DispatchTime.now()
        let got = try session.decodeStaff(tensor: tensor)
        let ms = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000
        let divergence = Gate1Oracle.firstMismatch(got, expected).map { i in
            (index: i,
             got: i < got.count ? got[i].description : "<end>",
             expected: i < expected.count ? expected[i].description : "<end>")
        }
        let result = Gate1Result(
            input: input,
            matched: Gate1Oracle.matchedCount(got, expected),
            expectedCount: expected.count,
            gotCount: got.count,
            divergence: divergence,
            decodeMs: ms,
            encoderProvider: "\(models.encoderBackend.provider)",
            ortVersion: ORTCSession.runtimeVersion
        )
        log.notice("Gate-1 (\(input, privacy: .public)): \(result.verdict, privacy: .public); \(result.detail, privacy: .public); got \(got.count) symbols")
        return result
    }
}
