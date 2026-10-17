import XCTest
@testable import OMRSheetCam

/// P2.2: after a successful scan, free users with <= 2 scans left (or on their 3rd lifetime scan) see a
/// soft, dismissible card, but only when the shared policy allows it and never for Pro.
/// Pure logic; also runs on Linux via a scratch SwiftPM harness.
final class PostScanCardTests: XCTestCase {
    func testShownWhenTwoOrFewerScansRemain() {
        for r in 0...2 {
            XCTAssertTrue(PostScanCard.shouldShow(remaining: r, isPro: false, lifetimeSuccesses: 10, policyAllows: true), "remaining \(r)")
        }
    }

    func testNotShownWhenPlentyRemainAndNotThirdScan() {
        XCTAssertFalse(PostScanCard.shouldShow(remaining: 4, isPro: false, lifetimeSuccesses: 1, policyAllows: true))
        XCTAssertFalse(PostScanCard.shouldShow(remaining: 3, isPro: false, lifetimeSuccesses: 4, policyAllows: true))
    }

    func testShownOnTheThirdLifetimeSuccessfulScan() {
        XCTAssertTrue(PostScanCard.shouldShow(remaining: 3, isPro: false, lifetimeSuccesses: 3, policyAllows: true))
    }

    func testNeverForPro() {
        XCTAssertFalse(PostScanCard.shouldShow(remaining: 0, isPro: true, lifetimeSuccesses: 3, policyAllows: true))
    }

    func testRespectsSharedPolicy() {
        XCTAssertFalse(PostScanCard.shouldShow(remaining: 1, isPro: false, lifetimeSuccesses: 3, policyAllows: false))
    }

    func testMessageCopyIsPlainNoPressure() {
        XCTAssertEqual(PostScanCard.message(remaining: 2), "2 scans left today. Pro is unlimited.")
        XCTAssertEqual(PostScanCard.message(remaining: 1), "1 scan left today. Pro is unlimited.")
        XCTAssertEqual(PostScanCard.message(remaining: 0), "0 scans left today. Pro is unlimited.")
        XCTAssertEqual(PostScanCard.message(remaining: 4), "Pro gives you unlimited scans.")
    }

    func testLifetimeCounterIncrements() {
        let d = UserDefaults(suiteName: UUID().uuidString)!
        XCTAssertEqual(PostScanCard.recordSuccess(defaults: d), 1)
        XCTAssertEqual(PostScanCard.recordSuccess(defaults: d), 2)
        XCTAssertEqual(PostScanCard.recordSuccess(defaults: d), 3)
    }
}
