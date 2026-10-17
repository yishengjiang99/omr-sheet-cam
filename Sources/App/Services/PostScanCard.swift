import Foundation

/// Soft upgrade card shown on the Result screen after a successful scan (P2.2).
/// Shown to free users with <= 2 scans left, or on their 3rd lifetime successful scan, and only when
/// the shared `UpgradePromptPolicy` allows an unsolicited prompt. Never for Pro.
enum PostScanCard {
    /// Also offer the card on this (lifetime) successful scan even when plenty of free scans remain.
    static let lifetimeTrigger = 3
    static let lifetimeKey = "omr.lifetimeScans"

    static func shouldShow(remaining: Int, isPro: Bool, lifetimeSuccesses: Int, policyAllows: Bool) -> Bool {
        guard !isPro, policyAllows else { return false }
        return remaining <= ScansLeft.nudgeThreshold || lifetimeSuccesses == lifetimeTrigger
    }

    static func message(remaining: Int) -> String {
        guard remaining <= ScansLeft.nudgeThreshold else { return "Pro gives you unlimited scans." }
        return "\(remaining) \(remaining == 1 ? "scan" : "scans") left today. Pro is unlimited."
    }

    /// Increment and return the lifetime count of successful scans (`omr.lifetimeScans`).
    @discardableResult
    static func recordSuccess(defaults: UserDefaults = .standard) -> Int {
        let n = defaults.integer(forKey: lifetimeKey) + 1
        defaults.set(n, forKey: lifetimeKey)
        return n
    }
}
