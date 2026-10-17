import Foundation

/// What the Settings "Music Reader Pro" section shows (StoreKit-free, testable anywhere).
enum ProSettingsRow: String, Equatable, Sendable {
    case status, upgrade, restore, manage
}

enum ProSettings {
    /// Rows for the section. Restore is always there (App Review 3.1.1), with zero scans used.
    static func rows(isPro: Bool) -> [ProSettingsRow] {
        []
    }

    static func statusText(isPro: Bool, scansRemaining: Int, dailyLimit: Int) -> String {
        ""
    }

    /// Toast after tapping Restore (`nil` = say nothing).
    static func restoreToast(_ outcome: RestoreOutcome) -> String? {
        nil
    }
}
