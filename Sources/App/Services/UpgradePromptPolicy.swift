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

/// Shared upgrade-prompt policy (P2.1). TODO: legacy behaviour has no policy at all.
final class UpgradePromptPolicy {
    init(defaults: UserDefaults, clock: @escaping () -> Date = Date.init, calendar: Calendar = .current) {}
    static let shared = UpgradePromptPolicy(defaults: .standard)

    func decision(for reason: PaywallReason, isPro: Bool, purchaseInProgress: Bool) -> UpsellDecision { .show }
    func recordShown(_ reason: PaywallReason) {}
    func recordDismissed(_ reason: PaywallReason) {}
}
