import Foundation

/// Gentle, capped upgrade reminder when a free user returns to the app after a few days (P2.9).
/// A dismissible banner on the Library (never a sheet, never mid-flow). Qualifies when the previous
/// foreground was >= 3 days ago and the user has not tapped "Not now" in the last 7 days; then the shared
/// `UpgradePromptPolicy` decides (no first session, 1/day, 3/7 days, never Pro or during a purchase).
@MainActor
final class ReturnReminder: ObservableObject {
    static let shared = ReturnReminder()
    static let minAbsence: TimeInterval = 3 * 86_400
    static let snooze: TimeInterval = 7 * 86_400
    static let lastActiveKey = "omr.lastActiveAt"
    static let notNowKey = "omr.returnNotNowAt"

    @Published private(set) var showBanner = false

    private let defaults: UserDefaults
    private let clock: () -> Date
    private var reportedAppearance = false

    init(defaults: UserDefaults = .standard, clock: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.clock = clock
    }

    nonisolated static func qualifies(previousActive: Date?, notNowAt: Date?, now: Date) -> Bool {
        guard let previousActive, now.timeIntervalSince(previousActive) >= minAbsence else { return false }
        if let notNowAt, now.timeIntervalSince(notNowAt) < snooze { return false }
        return true
    }

    /// Call on every foreground (cold start included), *after* the entitlement refresh so Pro/lapsed
    /// state is correct before deciding.
    func appBecameActive(quota: ScanQuota, purchaseInFlight: Bool) {
        let now = clock()
        let previous = date(Self.lastActiveKey)
        defaults.set(now.timeIntervalSince1970, forKey: Self.lastActiveKey)
        if quota.storeKit.isPro { showBanner = false; return }
        guard Self.qualifies(previousActive: previous, notNowAt: date(Self.notNowKey), now: now) else { return }
        guard quota.shouldShowPrompt(.appReturn, purchaseInProgress: purchaseInFlight) else { return }
        reportedAppearance = false
        showBanner = true
    }

    /// The banner is actually on screen (Library visible): count it once against the shared cap.
    func bannerAppeared(quota: ScanQuota) {
        guard showBanner, !reportedAppearance else { return }
        reportedAppearance = true
        quota.promptShown(.appReturn)
        Analytics.shared.track("upgrade_card_view", props: ["reason": PaywallReason.appReturn.analyticsValue])
    }

    /// "Not now": hide, snooze 7 days, and stay quiet for the rest of the session.
    func dismiss(quota: ScanQuota) {
        showBanner = false
        defaults.set(clock().timeIntervalSince1970, forKey: Self.notNowKey)
        quota.promptDismissed(.appReturn)
        Analytics.shared.track("upgrade_card_dismiss", props: ["reason": PaywallReason.appReturn.analyticsValue])
    }

    /// "See Pro": user-initiated, opens the paywall (uncapped) and hides the banner.
    func seeProTapped(quota: ScanQuota) {
        showBanner = false
        quota.requestPaywall(.appReturn)
    }

    private func date(_ key: String) -> Date? {
        guard defaults.object(forKey: key) != nil else { return nil }
        return Date(timeIntervalSince1970: defaults.double(forKey: key))
    }
}
