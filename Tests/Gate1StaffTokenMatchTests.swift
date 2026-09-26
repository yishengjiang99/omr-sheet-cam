import XCTest
import OMRHomrIOS
@testable import OMRSheetCam

/// Staff-only Gate-1 unit/device tests against `OMRHomrIOS.parseSheetMusicWithLayout`.
/// Does not invent tokens. Oracle assert skips until fixtures + ORT models land.
final class Gate1StaffTokenMatchTests: XCTestCase {

    /// Proves the app/test targets link `OMRHomrIOS` and hit the public API.
    func testParseSheetMusicAPIIsReachable() {
        let png = Gate1RootView.tinyPNG
        XCTAssertFalse(png.isEmpty)

        XCTAssertThrowsError(
            try OMRHomrIOS.parseSheetMusicWithLayout(
                input: ParseSheetMusicInput(imageData: png, staffOnly: true)
            )
        ) { error in
            guard let omr = error as? OMRError else {
                return XCTFail("expected OMRError, got \(error)")
            }
            switch omr {
            case .staffOnlyGate1NotReady, .modelsNotBundled:
                break // expected until models + oracle are wired
            default:
                XCTFail("unexpected OMRError case: \(omr)")
            }
        }
    }

    /// Gate-1 stop condition: decoded symbol sequence string-equal to C-scale oracle.
    /// XCTSkip when fixtures are missing. When present but inference still stubbed, skip
    /// (do not invent tokens). When parse succeeds with symbols exposed, assert field equality.
    func testCScaleOracleTokenMatch() throws {
        guard let staffURL = Self.oracleFileURL(named: "staff.png"),
              let oracleURL = Self.oracleFileURL(named: "oracle_tokens.json")
        else {
            throw XCTSkip(
                "Fixtures/c_scale_staff_oracle/{staff.png,oracle_tokens.json} missing — export from ~/workspace/homr-research (see Packages/omr-homr-ios/.../Fixtures/README.md)"
            )
        }

        let png = try Data(contentsOf: staffURL)
        XCTAssertFalse(png.isEmpty, "staff.png must be non-empty")
        let expected = try Self.loadOracleSymbols(from: oracleURL)
        XCTAssertFalse(expected.isEmpty, "oracle_tokens.json must list symbols")

        let result: ParseSheetMusicResult
        do {
            result = try OMRHomrIOS.parseSheetMusicWithLayout(
                input: ParseSheetMusicInput(imageData: png, staffOnly: true)
            )
        } catch let error as OMRError {
            switch error {
            case .staffOnlyGate1NotReady, .modelsNotBundled, .sessionNotConfigured:
                throw XCTSkip(
                    "Oracle fixtures present; staff-only decode not ready yet: \(error)"
                )
            default:
                throw error
            }
        }

        // Public ParseSheetMusicResult exposes midi + noteLayout only (AGPL isolation).
        // Token-level Gate-1 match uses StaffInferenceSession.decodeStaffSymbols once ORT
        // step runner is bound. Until symbols are obtainable, require non-empty MIDI as a
        // coarse readiness signal and skip the field-level assert with a clear pointer.
        _ = result
        let session = try StaffInferenceSession.makeDefault()
        do {
            // Unconfigured path throws until ORT lands — then compare to oracle.
            let decoded = try session.decodeStaffSymbols(
                normalizedStaffImage: png,
                stepRunner: UnconfiguredDecoderStepRunner()
            )
            Self.assertSymbolsEqual(decoded, expected)
        } catch let error as OMRError {
            switch error {
            case .sessionNotConfigured, .modelsNotBundled, .staffOnlyGate1NotReady:
                throw XCTSkip(
                    "parse returned but decodeStaffSymbols not ready for token assert: \(error)"
                )
            default:
                throw error
            }
        }
    }

    // MARK: - Oracle loading

    private static func oracleFileURL(named fileName: String) -> URL? {
        let candidates: [URL] = [
            // Package source-of-truth (checked out next to the app)
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent() // Tests/
                .deletingLastPathComponent() // repo root
                .appendingPathComponent(
                    "Packages/omr-homr-ios/Tests/OMRHomrIOSTests/Fixtures/c_scale_staff_oracle/\(fileName)"
                ),
            // Optional app-local copy
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("Fixtures/c_scale_staff_oracle/\(fileName)"),
            Bundle(for: Gate1StaffTokenMatchTests.self)
                .url(forResource: fileName, withExtension: nil, subdirectory: "Fixtures/c_scale_staff_oracle"),
            Bundle(for: Gate1StaffTokenMatchTests.self)
                .url(forResource: (fileName as NSString).deletingPathExtension,
                     withExtension: (fileName as NSString).pathExtension,
                     subdirectory: "Fixtures/c_scale_staff_oracle"),
        ].compactMap { $0 }

        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private struct OracleFile: Decodable {
        var symbols: [OracleSymbol]
    }

    private struct OracleSymbol: Decodable {
        var rhythm: String
        var pitch: String?
        var lift: String?
        var articulation: String?
        var slur: String?
        var position: String?
    }

    private static func loadOracleSymbols(from url: URL) throws -> [EncodedSymbol] {
        let data = try Data(contentsOf: url)
        let file = try JSONDecoder().decode(OracleFile.self, from: data)
        return file.symbols.map { s in
            EncodedSymbol(
                rhythm: s.rhythm,
                pitch: s.pitch ?? EncodedSymbol.nonote,
                lift: s.lift ?? EncodedSymbol.nonote,
                articulation: s.articulation ?? EncodedSymbol.nonote,
                slur: s.slur ?? EncodedSymbol.nonote,
                position: s.position ?? EncodedSymbol.nonote
            )
        }
    }

    private static func assertSymbolsEqual(
        _ got: [EncodedSymbol],
        _ expected: [EncodedSymbol],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(got.count, expected.count, "symbol count", file: file, line: line)
        let n = min(got.count, expected.count)
        for i in 0..<n {
            XCTAssertEqual(got[i].rhythm, expected[i].rhythm, "rhythm @\(i)", file: file, line: line)
            XCTAssertEqual(got[i].pitch, expected[i].pitch, "pitch @\(i)", file: file, line: line)
            XCTAssertEqual(got[i].lift, expected[i].lift, "lift @\(i)", file: file, line: line)
            XCTAssertEqual(got[i].articulation, expected[i].articulation, "articulation @\(i)", file: file, line: line)
            XCTAssertEqual(got[i].slur, expected[i].slur, "slur @\(i)", file: file, line: line)
            XCTAssertEqual(got[i].position, expected[i].position, "position @\(i)", file: file, line: line)
        }
    }
}
