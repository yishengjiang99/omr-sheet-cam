import XCTest
@testable import OMRSheetCam

/// P2.9: a once-in-a-while, dismissible banner when a free user returns after >= 3 days; "Not now"
/// snoozes it for 7 days; never for Pro, never in the first session, always through the shared policy.
@MainActor
final class ReturnReminderTests: XCTestCase {
    private final class FakePro: ProEntitlementSource {
        var isPro: Bool
        init(pro: Bool = false) { isPro = pro }
        func refreshEntitlements() async {}
    }

    private var now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86_400

    private func make(pro: Bool = false, firstSession: Bool = false) -> (ReturnReminder, ScanQuota) {
        let d = UserDefaults(suiteName: UUID().uuidString)!
        if !firstSession { d.set(now.addingTimeInterval(-60 * day).timeIntervalSince1970, forKey: UpgradePromptPolicy.firstLaunchKey) }
        let policy = UpgradePromptPolicy(defaults: d, clock: { [unowned self] in self.now })
        let quota = ScanQuota(storeKit: FakePro(pro: pro), promptPolicy: policy)
        let reminder = ReturnReminder(defaults: UserDefaults(suiteName: UUID().uuidString)!, clock: { [unowned self] in self.now })
        return (reminder, quota)
    }

    func testQualifiesOnlyAfterThreeDaysAway() {
        XCTAssertFalse(ReturnReminder.qualifies(previousActive: now.addingTimeInterval(-2 * day), notNowAt: nil, now: now))
        XCTAssertTrue(ReturnReminder.qualifies(previousActive: now.addingTimeInterval(-3 * day), notNowAt: nil, now: now))
        XCTAssertFalse(ReturnReminder.qualifies(previousActive: nil, notNowAt: nil, now: now), "first ever launch")
    }

    func testNotNowSnoozesForSevenDays() {
        let away = now.addingTimeInterval(-5 * day)
        XCTAssertFalse(ReturnReminder.qualifies(previousActive: away, notNowAt: now.addingTimeInterval(-6 * day), now: now))
        XCTAssertTrue(ReturnReminder.qualifies(previousActive: away, notNowAt: now.addingTimeInterval(-7 * day), now: now))
    }

    func testBannerAppearsWhenReturningAfterDays() {
        let (r, q) = make()
        r.appBecameActive(quota: q, purchaseInFlight: false) // records "last active = now"
        XCTAssertFalse(r.showBanner, "first foreground has no previous visit")
        now = now.addingTimeInterval(4 * day)
        r.appBecameActive(quota: q, purchaseInFlight: false)
        XCTAssertTrue(r.showBanner)
    }

    func testNoBannerOnShortGap() {
        let (r, q) = make()
        r.appBecameActive(quota: q, purchaseInFlight: false)
        now = now.addingTimeInterval(1 * day)
        r.appBecameActive(quota: q, purchaseInFlight: false)
        XCTAssertFalse(r.showBanner)
    }

    func testNeverForProOrFirstSessionOrInFlightPurchase() {
        for (pro, first, busy) in [(true, false, false), (false, true, false), (false, false, true)] {
            let (r, q) = make(pro: pro, firstSession: first)
            r.appBecameActive(quota: q, purchaseInFlight: busy)
            now = now.addingTimeInterval(4 * day)
            r.appBecameActive(quota: q, purchaseInFlight: busy)
            XCTAssertFalse(r.showBanner, "pro=\(pro) first=\(first) busy=\(busy)")
        }
    }

    func testDismissHidesAndSnoozes() {
        let (r, q) = make()
        r.appBecameActive(quota: q, purchaseInFlight: false)
        now = now.addingTimeInterval(4 * day)
        r.appBecameActive(quota: q, purchaseInFlight: false)
        r.dismiss(quota: q)
        XCTAssertFalse(r.showBanner)
        now = now.addingTimeInterval(4 * day) // away again, but still inside the 7-day snooze
        r.appBecameActive(quota: q, purchaseInFlight: false)
        XCTAssertFalse(r.showBanner)
    }

    func testSeeProOpensPaywallWithReasonAndHidesBanner() {
        let (r, q) = make()
        r.appBecameActive(quota: q, purchaseInFlight: false)
        now = now.addingTimeInterval(4 * day)
        r.appBecameActive(quota: q, purchaseInFlight: false)
        r.seeProTapped(quota: q)
        XCTAssertFalse(r.showBanner)
        XCTAssertTrue(q.showPaywall)
        XCTAssertEqual(q.paywallReason, .appReturn)
    }

    func testBannerAppearanceCountsAgainstTheSharedCap() {
        let (r, q) = make()
        r.appBecameActive(quota: q, purchaseInFlight: false)
        now = now.addingTimeInterval(4 * day)
        r.appBecameActive(quota: q, purchaseInFlight: false)
        r.bannerAppeared(quota: q)
        XCTAssertFalse(q.shouldShowPrompt(.postScan), "one unsolicited prompt per day across all surfaces")
    }
}
