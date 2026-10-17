import Foundation

/// What the Settings "Music Reader Pro" section shows (StoreKit-free, testable anywhere).
enum ProSettingsRow: String, Equatable, Sendable {
    case status, upgrade, restore, manage
}

enum ProSettings {
    /// Rows for the section. Restore is always there (App Review 3.1.1), with zero scans used.
    static func rows(isPro: Bool) -> [ProSettingsRow] {
        isPro ? [.status, .manage, .restore] : [.status, .upgrade, .restore]
    }

    static func statusText(isPro: Bool, scansRemaining: Int, dailyLimit: Int) -> String {
        if isPro { return "Music Reader Pro: active" }
        if scansRemaining <= 0 { return "Free plan: no scans left today" }
        return "Free plan: \(scansRemaining) of \(dailyLimit) scans left today"
    }

    /// Toast after tapping Restore (`nil` = say nothing).
    static func restoreToast(_ outcome: RestoreOutcome) -> String? {
        switch outcome {
        case .restored: return "Pro restored"
        case .nothingToRestore: return "No active subscription found for this Apple ID"
        case .cancelled, .failed(.cancelled): return nil
        case .failed(let kind): return PurchaseResolver.userMessage(for: kind)
        }
    }
}
