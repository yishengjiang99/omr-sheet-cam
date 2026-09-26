import Foundation
import XCTest
@testable import OMRSheetCam

/// The in-app "Run Gate-1" path (same `Gate1Runner` the button calls): warmed sessions from
/// `ModelWarmup` (`OMR_MODELS_DIR` in ios-sim CI, else bundled models) + fixtures bundled in
/// `<App>.app/gate1/`. Must match homr's 12 tokens exactly.
final class Gate1RunnerTests: XCTestCase {
    @MainActor
    func testBundledNPYRunMatchesOracle() async throws {
        let env = ProcessInfo.processInfo.environment["OMR_MODELS_DIR"] ?? ""
        let dir = env.isEmpty ? nil : URL(fileURLWithPath: env, isDirectory: true)
        let fixtures = try Gate1Runner.bundledFixturesDir()
        for name in ["staff.npy", "staff.png", "expected.tokens.json"] {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: fixtures.appendingPathComponent(name).path),
                "gate1/\(name) not bundled"
            )
        }
        let models = try await ModelWarmup.shared.readyModels(modelsDir: dir)
        let result = try await Task.detached(priority: .userInitiated) {
            XCTAssertFalse(Thread.isMainThread)
            return try Gate1Runner.runNPY(models: models)
        }.value
        print("Gate1Runner: \(result.verdict) | \(result.detail)")
        XCTAssertEqual(result.verdict, "PASS 12/12")
        XCTAssertTrue(result.passed)
        XCTAssertEqual(result.matched, 12)
        XCTAssertEqual(result.gotCount, 12)
        XCTAssertEqual(result.encoderProvider, "coreML")
        XCTAssertGreaterThan(result.decodeMs, 0)
    }
}
