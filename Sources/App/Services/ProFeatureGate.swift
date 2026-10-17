import Foundation

/// Contextual upgrade prompt on locked Pro features (P9.1). Always on (product decision by Yisheng;
/// there is no feature flag). Free users who try a gated feature see the soft, dismissible paywall
/// (reason `feature_<name>`); Pro users are never prompted. Only Transpose is gated, and saved
/// content (playback of existing scans, share, Library) is never gated.
enum ProFeature: String, CaseIterable {
    case transpose
}

enum ProFeatureGate {
    /// Features that need Pro. Gate at the action (a tap), never at the screen.
    static let gated: Set<ProFeature> = [.transpose]

    static func allows(_ feature: ProFeature, isPro: Bool) -> Bool {
        isPro || !gated.contains(feature)
    }

    static func paywallReason(for feature: ProFeature) -> PaywallReason {
        .feature(feature.rawValue)
    }
}
