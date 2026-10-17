import XCTest
@testable import OMRSheetCam

/// P6.1: Settings has a Pro section with Restore (reachable without hitting the paywall), Manage
/// subscription for Pro users, and plain-language Restore feedback. Pure logic (also runs on Linux
/// via a scratch SwiftPM harness).
final class ProSettingsTests: XCTestCase {
    func testRestoreRowIsAlwaysPresent() {
        XCTAssertTrue(ProSettings.rows(isPro: false).contains(.restore), "free users must find Restore without using 5 scans")
        XCTAssertTrue(ProSettings.rows(isPro: true).contains(.restore))
    }

    func testFreeUserSeesUpgradeNotManage() {
        let rows = ProSettings.rows(isPro: false)
        XCTAssertEqual(rows.first, .status)
        XCTAssertTrue(rows.contains(.upgrade))
        XCTAssertFalse(rows.contains(.manage))
    }

    func testProUserSeesManageNotUpgrade() {
        let rows = ProSettings.rows(isPro: true)
        XCTAssertEqual(rows.first, .status)
        XCTAssertTrue(rows.contains(.manage))
        XCTAssertFalse(rows.contains(.upgrade))
    }

    func testStatusText() {
        XCTAssertEqual(ProSettings.statusText(isPro: true, scansRemaining: Int.max, dailyLimit: 5), "Music Reader Pro: active")
        XCTAssertEqual(ProSettings.statusText(isPro: false, scansRemaining: 3, dailyLimit: 5), "Free plan: 3 of 5 scans left today")
        XCTAssertEqual(ProSettings.statusText(isPro: false, scansRemaining: 1, dailyLimit: 5), "Free plan: 1 of 5 scans left today")
        XCTAssertEqual(ProSettings.statusText(isPro: false, scansRemaining: 0, dailyLimit: 5), "Free plan: no scans left today")
    }

    func testRestoreToasts() {
        XCTAssertEqual(ProSettings.restoreToast(.restored), "Pro restored")
        XCTAssertEqual(ProSettings.restoreToast(.nothingToRestore), "No active subscription found for this Apple ID")
        XCTAssertNil(ProSettings.restoreToast(.cancelled), "dismissing the Apple ID prompt is silent")
        XCTAssertEqual(ProSettings.restoreToast(.failed(.network)), PurchaseResolver.userMessage(for: .network))
    }
}
