import Foundation

/// Soft upgrade card shown on the Result screen after a successful scan (P2.2).
/// TODO: stub (legacy behaviour: no card ever).
enum PostScanCard {
    /// Also offer the card on this (lifetime) successful scan even when plenty of free scans remain.
    static let lifetimeTrigger = 3

    static func shouldShow(remaining: Int, isPro: Bool, lifetimeSuccesses: Int, policyAllows: Bool) -> Bool { false }

    static func message(remaining: Int) -> String { "" }

    /// Increment and return the lifetime count of successful scans (`omr.lifetimeScans`).
    static func recordSuccess(defaults: UserDefaults = .standard) -> Int { 0 }
}
