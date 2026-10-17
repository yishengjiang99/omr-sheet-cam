import Foundation

/// Contextual upgrade prompt on locked Pro features (P9.1). TODO: stub (legacy: nothing is ever locked).
enum ProFeature: String, CaseIterable {
    case transpose
}

enum ProFeatureGate {
    static let flagKey = "omr.flag.lockedFeatures"
    static let gatedWhenEnabled: Set<ProFeature> = [.transpose]

    static func flagEnabled(defaults: UserDefaults = .standard) -> Bool { true }
    static func allows(_ feature: ProFeature, isPro: Bool, flagEnabled: Bool) -> Bool { true }
    static func paywallReason(for feature: ProFeature) -> PaywallReason { .quota }
}
