import Foundation

/// Free tier: 5 scans per day. Pro users have no limit.
///
/// A scan is only *charged* when recognition succeeds: `canScan()` is a read-only gate before the
/// scan starts, `commit()` records the use once the scan was recognized. Failed, cancelled and
/// reader-not-ready scans never call `commit()`, so they cost nothing (P1.4).
@MainActor
final class ScanQuota: ObservableObject {
    static let shared = ScanQuota()
    static let freeDailyLimit = 5

    private let countKey = "omr.freeScansUsed"
    private let dateKey = "omr.freeScansDate"
    /// Injected (default: the app-wide manager) so the gate and the UI share one StoreKitManager.
    let storeKit: StoreKitManager
    private let defaults: UserDefaults
    private let isPro: @MainActor () -> Bool
    private let track: @MainActor (String, [String: String]) -> Void

    @Published var showPaywall = false

    /// Defaults: the shared StoreKit manager (Pro status), `UserDefaults.standard`, `Analytics.shared`.
    /// Tests inject `defaults` / `isPro` / `track`.
    init(
        storeKit: StoreKitManager = .shared,
        defaults: UserDefaults = .standard,
        isPro: (@MainActor () -> Bool)? = nil,
        track: (@MainActor (String, [String: String]) -> Void)? = nil
    ) {
        self.storeKit = storeKit
        self.defaults = defaults
        self.isPro = isPro ?? { storeKit.isPro }
        self.track = track ?? { Analytics.shared.track($0, props: $1) }
    }

    private var today: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    /// Read-only gate: true if the user may start a scan now. Does NOT consume quota. If false
    /// (free limit reached), tracks the paywall trigger and sets `showPaywall`.
    func canScan() -> Bool {
        if isPro() { return true }
        rollDateIfNeeded()
        if defaults.integer(forKey: countKey) >= Self.freeDailyLimit {
            track("free_quota_hit", [:])
            track("paywall_trigger", ["reason": "quota"])
            showPaywall = true
            return false
        }
        return true
    }

    /// Charges one free scan. Call exactly once per scan, only after recognition succeeded.
    func commit() {
        if isPro() { return }
        rollDateIfNeeded()
        defaults.set(defaults.integer(forKey: countKey) + 1, forKey: countKey)
    }

    private func rollDateIfNeeded() {
        if defaults.string(forKey: dateKey) != today {
            defaults.set(today, forKey: dateKey)
            defaults.set(0, forKey: countKey)
        }
    }

    var scansRemaining: Int {
        if isPro() { return Int.max }
        let lastDate = defaults.string(forKey: dateKey)
        if lastDate != today { return Self.freeDailyLimit }
        return max(0, Self.freeDailyLimit - defaults.integer(forKey: countKey))
    }
}
