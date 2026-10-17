import Foundation

/// Contextual upgrade prompt on locked Pro features (P9.1).
///
/// **Ships OFF.** Today Pro unlocks only unlimited scans; the paywall copy, ASC description and review
/// notes all say every other feature is free. Gating anything is a product decision, so the flag
/// (`omr.flag.lockedFeatures`, default false; set via defaults or the launch argument
/// `-omr.flag.lockedFeatures YES`) must stay off until that decision is made AND the paywall comparison,
/// ASC description, review notes and privacy page list the real differences.
/// Saved content (playback of existing scans, share, Library) is never gated.
enum ProFeature: String, CaseIterable {
    case transpose
}

enum ProFeatureGate {
    static let flagKey = "omr.flag.lockedFeatures"
    /// Candidate feature(s) gated when the flag is on (new/optional controls only, never saved content).
    static let gatedWhenEnabled: Set<ProFeature> = [.transpose]

    static func flagEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: flagKey)
    }

    static func allows(_ feature: ProFeature, isPro: Bool, flagEnabled: Bool) -> Bool {
        !flagEnabled || isPro || !gatedWhenEnabled.contains(feature)
    }

    static func paywallReason(for feature: ProFeature) -> PaywallReason {
        .feature(feature.rawValue)
    }
}
