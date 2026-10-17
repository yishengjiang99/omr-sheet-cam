import XCTest
@testable import OMRSheetCam

/// P3.7: the photo that hit the paywall is not lost when the user subscribes. Pure logic (also runs on
/// Linux via a scratch SwiftPM harness).
final class PendingScanTests: XCTestCase {
    func testHeldPhotoIsResubmittedOnceWhenUserBecamePro() {
        var pending = PendingScan<String>()
        pending.hold("page1")
        XCTAssertEqual(pending.take(isPro: true), "page1", "after purchase the same photo must continue into Reading")
        XCTAssertNil(pending.take(isPro: true), "must be re-submitted exactly once")
    }

    func testHeldPhotoIsDroppedWhenPaywallClosedWhileStillFree() {
        var pending = PendingScan<String>()
        pending.hold("page1")
        XCTAssertNil(pending.take(isPro: false))
        XCTAssertNil(pending.take(isPro: true), "Close must clear it; a later purchase must not resurrect an old photo")
    }

    func testNewerRejectedPhotoReplacesOlderOne() {
        var pending = PendingScan<String>()
        pending.hold("old")
        pending.hold("new")
        XCTAssertEqual(pending.take(isPro: true), "new")
    }

    func testNothingHeldNothingTaken() {
        var pending = PendingScan<String>()
        XCTAssertNil(pending.take(isPro: true))
    }
}
