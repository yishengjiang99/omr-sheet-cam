import Foundation
import XCTest
@testable import OMRSheetCam

/// App warmup against `OMR_MODELS_DIR` (ios-sim CI: `TEST_RUNNER_OMR_MODELS_DIR`), else the
/// models bundled in the host app. Must reach `.ready` with non-zero timings, off the main thread.
final class ModelWarmupTests: XCTestCase {
    @MainActor
    func testWarmupReachesReadyOffMainThread() async throws {
        let env = ProcessInfo.processInfo.environment["OMR_MODELS_DIR"] ?? ""
        let dir = env.isEmpty ? nil : URL(fileURLWithPath: env, isDirectory: true)
        let warmup = ModelWarmup()
        XCTAssertEqual(warmup.state, .idle)
        let task = warmup.start(modelsDir: dir)
        XCTAssertEqual(warmup.state, .warming, "start() must return before the work finishes")
        let report = await task.value
        XCTAssertEqual(warmup.state, .ready, warmup.debugLine)
        let r = try XCTUnwrap(report, warmup.debugLine)
        XCTAssertFalse(r.ranOnMainThread, "warmup ran on the main thread")
        XCTAssertEqual(r.sessions.map(\.name), ["segnet", "encoder", "decoder"])
        XCTAssertEqual(r.sessions.map(\.provider), ["coreML", "coreML", "cpu"])
        for s in r.sessions {
            XCTAssertGreaterThan(s.createMs, 0, "\(s.name) create ms")
            XCTAssertGreaterThan(s.firstRunMs, 0, "\(s.name) first run ms")
            XCTAssertGreaterThan(s.footprintMB, 0, "\(s.name) footprint")
        }
        XCTAssertGreaterThan(r.totalMs, 0)
        XCTAssertGreaterThanOrEqual(r.peakMB, r.endMB)
        XCTAssertGreaterThan(r.peakMB, 0)
        print("Warmup: \(warmup.debugLine)")
        r.lines.forEach { print("Warmup: \($0)") }
    }
}
