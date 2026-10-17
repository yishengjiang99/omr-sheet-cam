import XCTest
@testable import OMRSheetCam

/// P2.1: one shared policy for every upsell surface (cap, first-session, Pro and in-flight suppression).
/// Pure logic with an injected clock and defaults suite; also runs on Linux via a scratch SwiftPM harness.
final class UpgradePromptPolicyTests: XCTestCase {
    private var now = Date(timeIntervalSince1970: 1_800_000_000) // fixed instant
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func makePolicy(suite: String = UUID().uuidString, firstSessionOver: Bool = true) -> (UpgradePromptPolicy, String) {
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        if firstSessionOver {
            // A previous launch happened long ago, so this is not the first session.
            d.set(now.addingTimeInterval(-30 * 86_400).timeIntervalSince1970, forKey: "omr.upsell.firstLaunchAt")
        }
        return (UpgradePromptPolicy(defaults: d, clock: { [unowned self] in self.now }, calendar: calendar), suite)
    }

    private func decide(_ p: UpgradePromptPolicy, _ r: PaywallReason = .postScan,
                        pro: Bool = false, busy: Bool = false) -> UpsellDecision {
        p.decision(for: r, isPro: pro, purchaseInProgress: busy)
    }

    func testFreeUserNotInFirstSessionMayBeShownAnUnsolicitedPrompt() {
        let (p, _) = makePolicy()
        XCTAssertEqual(decide(p), .show)
    }

    func testNeverInTheFirstSession() {
        let (p, _) = makePolicy(firstSessionOver: false)
        XCTAssertEqual(decide(p), .suppressed(.firstSession))
        XCTAssertEqual(decide(p, .appReturn), .suppressed(.firstSession))
    }

    func testFirstSessionEndsOnTheNextPolicyInstance() {
        let (_, suite) = makePolicy(firstSessionOver: false)
        let d = UserDefaults(suiteName: suite)!
        let next = UpgradePromptPolicy(defaults: d, clock: { [unowned self] in self.now }, calendar: calendar)
        XCTAssertEqual(decide(next), .show, "second launch is not the first session")
    }

    func testProIsNeverPrompted() {
        let (p, _) = makePolicy()
        XCTAssertEqual(decide(p, pro: true), .suppressed(.pro))
        XCTAssertEqual(decide(p, .settings, pro: true), .suppressed(.pro))
    }

    func testPurchaseInProgressSuppresses() {
        let (p, _) = makePolicy()
        XCTAssertEqual(decide(p, busy: true), .suppressed(.purchaseInProgress))
    }

    func testQuotaWallIsExemptFromCapsAndFirstSession() {
        let (p, _) = makePolicy(firstSessionOver: false)
        for _ in 0..<5 { p.recordShown(.postScan) }
        XCTAssertEqual(decide(p, .quota), .show)
        XCTAssertEqual(decide(p, .settings), .show, "user-initiated entry points are not capped")
    }

    func testOnePerCalendarDay() {
        let (p, _) = makePolicy()
        p.recordShown(.postScan)
        now = now.addingTimeInterval(3_600) // an hour later, same UTC day
        XCTAssertEqual(decide(p), .suppressed(.dailyCap))
    }

    func testSixtySecondSpacing() {
        let (p, _) = makePolicy()
        p.recordShown(.postScan)
        now = now.addingTimeInterval(30)
        XCTAssertEqual(decide(p), .suppressed(.tooSoon))
    }

    func testNextDayAllowedUntilThreeInSevenDays() {
        let (p, _) = makePolicy()
        for _ in 0..<3 {
            XCTAssertEqual(decide(p), .show)
            p.recordShown(.postScan)
            now = now.addingTimeInterval(86_400 + 120) // next calendar day
        }
        XCTAssertEqual(decide(p), .suppressed(.weeklyCap))
        now = now.addingTimeInterval(5 * 86_400) // first one has aged out of the 7-day window
        XCTAssertEqual(decide(p), .show)
    }

    func testDismissalSilencesTheRestOfTheSession() {
        let (p, _) = makePolicy()
        p.recordDismissed(.postScan)
        now = now.addingTimeInterval(10 * 86_400)
        XCTAssertEqual(decide(p), .suppressed(.dismissedThisSession))
        XCTAssertEqual(decide(p, .quota), .show)
    }

    func testHistoryPersistsAcrossInstances() {
        let (p, suite) = makePolicy()
        p.recordShown(.appReturn)
        now = now.addingTimeInterval(3_600)
        let again = UpgradePromptPolicy(defaults: UserDefaults(suiteName: suite)!, clock: { [unowned self] in self.now }, calendar: calendar)
        XCTAssertEqual(decide(again), .suppressed(.dailyCap))
    }

    func testReasonAnalyticsValues() {
        XCTAssertEqual(PaywallReason.quota.analyticsValue, "quota")
        XCTAssertEqual(PaywallReason.postScan.analyticsValue, "post_scan")
        XCTAssertEqual(PaywallReason.feature("transpose").analyticsValue, "feature_transpose")
        XCTAssertTrue(PaywallReason.postScan.isUnsolicited)
        XCTAssertFalse(PaywallReason.quota.isUnsolicited)
    }

    // MARK: ScanQuota.requestPaywall (single presenter for every reason)

    @MainActor
    private final class FakePro: ProEntitlementSource {
        var isPro: Bool
        init(pro: Bool) { isPro = pro }
        func refreshEntitlements() async {}
    }

    @MainActor
    func testRequestPaywallOpensWithTheGivenReasonForFreeUsers() {
        let q = ScanQuota(storeKit: FakePro(pro: false), promptPolicy: makePolicy().0)
        XCTAssertTrue(q.requestPaywall(.settings))
        XCTAssertTrue(q.showPaywall)
        XCTAssertEqual(q.paywallReason, .settings)
    }

    @MainActor
    func testRequestPaywallNeverOpensForPro() {
        let q = ScanQuota(storeKit: FakePro(pro: true), promptPolicy: makePolicy().0)
        XCTAssertFalse(q.requestPaywall(.nudge))
        XCTAssertFalse(q.showPaywall)
    }

    @MainActor
    func testTappingSeeProOnAPromptSurfaceIsNotCapped() {
        let policy = makePolicy().0
        let q = ScanQuota(storeKit: FakePro(pro: false), promptPolicy: policy)
        XCTAssertTrue(q.shouldShowPrompt(.postScan))
        q.promptShown(.postScan)
        q.promptDismissed(.postScan)
        XCTAssertFalse(q.shouldShowPrompt(.appReturn), "cap and dismissal suppress further unsolicited surfaces")
        XCTAssertTrue(q.requestPaywall(.postScan), "but a user tap on See Pro always opens the paywall")
        XCTAssertEqual(q.paywallReason, .postScan)
    }

    @MainActor
    func testShouldShowPromptSuppressedForProAndInFlightPurchase() {
        let free = ScanQuota(storeKit: FakePro(pro: false), promptPolicy: makePolicy().0)
        XCTAssertFalse(free.shouldShowPrompt(.postScan, purchaseInProgress: true))
        let pro = ScanQuota(storeKit: FakePro(pro: true), promptPolicy: makePolicy().0)
        XCTAssertFalse(pro.shouldShowPrompt(.postScan))
    }
}
