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

    /// Warmup progress weights: one per step, summing to 1 (the "Warming up… x%" bar ends at 100%).
    func testWarmupProgressWeights() {
        XCTAssertEqual(ModelWarmup.warmupProgressWeights.count, 7, "segnet create/run, encoder create/run, vocab, decoder create/run")
        XCTAssertEqual(ModelWarmup.warmupProgressWeights.reduce(0, +), 1.0, accuracy: 1e-9)
        XCTAssertTrue(ModelWarmup.warmupProgressWeights.allSatisfy { $0 > 0 })
    }

    /// `attachProgressIfNeeded`: never auto-starts a first-ever warmup (launch owns that; a scan
    /// with a fake factory must not kick off real model loading).
    @MainActor
    func testAttachProgressIfNeededDoesNotStartFirstWarmup() {
        let warmup = ModelWarmup()
        var reports = 0
        XCTAssertFalse(warmup.attachProgressIfNeeded { _ in reports += 1 })
        XCTAssertEqual(warmup.state, .idle, "must not start a first-ever warmup")
        XCTAssertEqual(reports, 0)
    }
}
