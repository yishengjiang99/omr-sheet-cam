import Foundation

/// Why the paywall (or an upsell surface) is being shown. Sent as the `reason` property on
/// `paywall_trigger` / `paywall_view` / `paywall_dismiss`.
enum PaywallReason: Equatable, Hashable {
    case quota, postScan, nudge, settings, library, appReturn
    case feature(String)

    var analyticsValue: String {
        switch self {
        case .quota: return "quota"
        case .postScan: return "post_scan"
        case .nudge: return "nudge"
        case .settings: return "settings"
        case .library: return "library"
        case .appReturn: return "app_return"
        case .feature(let name): return "feature_\(name)"
        }
    }

    /// Surfaces that appear on their own (a card or banner the user did not ask for). Only these are
    /// subject to the frequency cap. Everything else opens because the user tapped or tried to scan.
    var isUnsolicited: Bool {
        switch self {
        case .postScan, .appReturn: return true
        case .quota, .nudge, .settings, .library, .feature: return false
        }
    }
}

enum UpsellSuppression: Equatable {
    case pro, purchaseInProgress, firstSession, dismissedThisSession, dailyCap, weeklyCap, tooSoon
}

enum UpsellDecision: Equatable {
    case show
    case suppressed(UpsellSuppression)
    var allowed: Bool { self == .show }
}

/// Shared upgrade-prompt policy (P2.1). Every unsolicited upsell surface (post-scan card, app-return
/// banner, ...) asks `decision(for:...)` before it appears and calls `recordShown` / `recordDismissed`.
///
/// Rules (App Review guardrails from the audit):
/// - never for Pro, and never while a purchase / restore / Ask-to-Buy approval is in flight
/// - never in the first session after install
/// - at most 1 unsolicited prompt per calendar day and 3 per rolling 7 days, >= 60 s apart
/// - after a dismissal, nothing unsolicited for the rest of the session
/// - user-initiated paywall openings (quota wall, Settings row, nudge tap, ...) are exempt from the cap
///   and are never recorded against it.
final class UpgradePromptPolicy {
    static let shared = UpgradePromptPolicy(defaults: .standard)

    static let lastShownKey = "omr.upsell.lastShownAt"
    static let shown7dKey = "omr.upsell.shown7d"
    static let firstLaunchKey = "omr.upsell.firstLaunchAt"
    static let minSpacing: TimeInterval = 60
    static let dailyLimit = 1
    static let weeklyLimit = 3
    private static let week: TimeInterval = 7 * 86_400

    private let defaults: UserDefaults
    private let clock: () -> Date
    private let calendar: Calendar
    private var dismissedThisSession = false
    /// True when this instance (= this launch) is the very first one for the install.
    let isFirstSession: Bool

    init(defaults: UserDefaults, clock: @escaping () -> Date = Date.init, calendar: Calendar = .current) {
        self.defaults = defaults
        self.clock = clock
        self.calendar = calendar
        if defaults.object(forKey: Self.firstLaunchKey) == nil {
            defaults.set(clock().timeIntervalSince1970, forKey: Self.firstLaunchKey)
            isFirstSession = true
        } else {
            isFirstSession = false
        }
    }

    func decision(for reason: PaywallReason, isPro: Bool, purchaseInProgress: Bool) -> UpsellDecision {
        if isPro { return .suppressed(.pro) }
        // The quota wall and explicit taps are user-initiated: exempt from every cap below.
        guard reason.isUnsolicited else { return .show }
        if purchaseInProgress { return .suppressed(.purchaseInProgress) }
        if isFirstSession { return .suppressed(.firstSession) }
        if dismissedThisSession { return .suppressed(.dismissedThisSession) }
        let now = clock()
        let shown = history(now: now)
        if let last = shown.max(), now.timeIntervalSince(last) < Self.minSpacing { return .suppressed(.tooSoon) }
        if shown.filter({ calendar.isDate($0, inSameDayAs: now) }).count >= Self.dailyLimit { return .suppressed(.dailyCap) }
        if shown.count >= Self.weeklyLimit { return .suppressed(.weeklyCap) }
        return .show
    }

    /// Call when an unsolicited surface actually appears. User-initiated openings are not recorded.
    func recordShown(_ reason: PaywallReason) {
        guard reason.isUnsolicited else { return }
        let now = clock()
        var shown = history(now: now)
        shown.append(now)
        defaults.set(shown.map(\.timeIntervalSince1970), forKey: Self.shown7dKey)
        defaults.set(now.timeIntervalSince1970, forKey: Self.lastShownKey)
    }

    /// Call when the user dismisses an unsolicited surface (card "x", banner "Not now", paywall close).
    func recordDismissed(_ reason: PaywallReason) {
        guard reason.isUnsolicited else { return }
        dismissedThisSession = true
    }

    /// Prompts shown in the last 7 days.
    private func history(now: Date) -> [Date] {
        let raw = defaults.array(forKey: Self.shown7dKey) as? [Double] ?? []
        return raw.map(Date.init(timeIntervalSince1970:)).filter { now.timeIntervalSince($0) < Self.week }
    }
}
