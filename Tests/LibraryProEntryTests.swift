import XCTest
@testable import OMRSheetCam

/// P9.4: free users get a quiet, self-serve "Go Pro" entry on the Library home; Pro users do not see it,
/// and it never appears on the Player's embedded Library sheet. Opening the paywall from it is
/// user-initiated (reason `library`, uncapped by the shared policy).
@MainActor
final class LibraryProEntryTests: XCTestCase {
    private final class FakePro: ProEntitlementSource {
        var isPro: Bool
        init(pro: Bool) { isPro = pro }
        func refreshEntitlements() async {}
    }

    func testVisibleForFreeUsersOnLibraryHome() {
        XCTAssertTrue(LibraryProEntry.isVisible(isPro: false, isHomeChrome: true))
        XCTAssertEqual(LibraryProEntry.title, "Go Pro")
    }

    func testHiddenForPro() {
        XCTAssertFalse(LibraryProEntry.isVisible(isPro: true, isHomeChrome: true))
    }

    func testHiddenOutsideLibraryHome() {
        XCTAssertFalse(LibraryProEntry.isVisible(isPro: false, isHomeChrome: false))
    }

    func testEntryOpensPaywallWithLibraryReasonEvenAfterDismissals() {
        let d = UserDefaults(suiteName: UUID().uuidString)!
        let policy = UpgradePromptPolicy(defaults: d)
        let q = ScanQuota(storeKit: FakePro(pro: false), promptPolicy: policy)
        q.promptDismissed(.postScan) // session already silenced for unsolicited prompts
        XCTAssertTrue(q.requestPaywall(.library))
        XCTAssertEqual(q.paywallReason, .library)
    }

    func testEntryNeverOpensPaywallForPro() {
        let q = ScanQuota(storeKit: FakePro(pro: true), promptPolicy: UpgradePromptPolicy(defaults: UserDefaults(suiteName: UUID().uuidString)!))
        XCTAssertFalse(q.requestPaywall(.library))
        XCTAssertFalse(q.showPaywall)
    }
}
