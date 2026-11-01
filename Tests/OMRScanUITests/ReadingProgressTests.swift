import Foundation
import OMRHomrIOS
import UIKit
import XCTest
@testable import OMRScanKit
@testable import OMRScanUI

/// Reading screen copy and the main-actor progress model behind it.
final class ReadingProgressTests: XCTestCase {
    /// Warmup subtitle falls back gracefully when no ETA is known yet.
    func testReadingViewSubtitleFallback() {
        XCTAssertEqual(
            ReadingView.subtitle(warmingUp: true, etaSeconds: nil),
            "One-time setup — loading the music models on your iPhone")
        XCTAssertEqual(
            ReadingView.subtitle(warmingUp: true, etaSeconds: 0.5),
            "One-time setup — loading the music models on your iPhone")
        XCTAssertEqual(
            ReadingView.subtitle(warmingUp: false, etaSeconds: 30),
            "This usually takes a few seconds")
    }

    /// Main-actor model behind the Reading screen: never decreases, clamps to 0...1, label "Reading music… 42%".
    @MainActor
    func testRecognitionProgressModelAndLabel() async {
        let m = RecognitionProgress()
        XCTAssertEqual(m.percent, 0)
        m.report(ScanProgress(warmingUp: false, fraction: 0.42))
        XCTAssertEqual(m.percent, 42)
        XCTAssertEqual(ReadingView.title(fraction: m.fraction), "Reading music… 42%")
        m.report(ScanProgress(warmingUp: false, fraction: 0.3))
        XCTAssertEqual(m.fraction, 0.42, "never goes down")
        m.report(ScanProgress(warmingUp: false, fraction: 1.5))
        XCTAssertEqual(m.fraction, 1)
        XCTAssertEqual(ReadingView.title(fraction: m.fraction), "Reading music… 100%")
        m.reset()
        XCTAssertEqual(m.fraction, 0)
        // Background reports hop to the main actor.
        let h = m.handler
        await Task.detached { h(ScanProgress(warmingUp: false, fraction: 0.25)) }.value
        for _ in 0..<50 where m.fraction == 0 { await Task.yield() }
        XCTAssertEqual(m.fraction, 0.25)
    }

    /// Phase change resets the bar: "Warming up… 90%" → "Reading music… 10%", never down within a phase.
    @MainActor
    func testRecognitionProgressPhaseChangeResets() {
        let m = RecognitionProgress()
        m.report(ScanProgress(warmingUp: true, fraction: 0.9))
        XCTAssertTrue(m.warmingUp)
        XCTAssertEqual(m.percent, 90)
        XCTAssertEqual(ReadingView.title(fraction: m.fraction, warmingUp: m.warmingUp), "Warming up… 90%")
        m.report(ScanProgress(warmingUp: false, fraction: 0.1))
        XCTAssertFalse(m.warmingUp)
        XCTAssertEqual(m.percent, 10, "phase change must reset the bar for the new phase")
        m.report(ScanProgress(warmingUp: false, fraction: 0.05))
        XCTAssertEqual(m.percent, 10, "never goes down within a phase")
        m.reset()
        XCTAssertEqual(m.percent, 0)
        XCTAssertFalse(m.warmingUp)
    }

    /// Warmup ETA: forwarded through the progress chain and cleared on phase change / reset.
    @MainActor
    func testRecognitionProgressForwardsWarmupETA() {
        let m = RecognitionProgress()
        m.report(ScanProgress(warmingUp: true, fraction: 0.2, etaSeconds: 30))
        XCTAssertTrue(m.warmingUp)
        XCTAssertEqual(m.etaSeconds, 30)
        XCTAssertEqual(
            ReadingView.subtitle(warmingUp: m.warmingUp, etaSeconds: m.etaSeconds),
            "About 30 seconds left · one-time setup")
        m.report(ScanProgress(warmingUp: true, fraction: 0.5, etaSeconds: 12))
        XCTAssertEqual(m.etaSeconds, 12, "ETA ticks down")
        m.report(ScanProgress(warmingUp: false, fraction: 0.1))
        XCTAssertNil(m.etaSeconds, "ETA cleared when the parse phase starts")
        m.reset()
        XCTAssertNil(m.etaSeconds)
    }
}
