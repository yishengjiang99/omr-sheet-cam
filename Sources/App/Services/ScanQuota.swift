import Foundation

/// Free tier: 5 scans per day. Pro users have no limit.
///
/// A scan is only *charged* when recognition succeeds: `canScan()` is a read-only gate before the
/// scan starts, `commit()` records the use once the scan was recognized. Failed, cancelled and
/// reader-not-ready scans never call `commit()`, so they cost nothing (P1.4).
@MainActor
final class ScanQuota: ObservableObject {
    static let shared = ScanQuota(storeKit: StoreKitManager.shared)
    static let freeDailyLimit = 5

    private let countKey = "omr.freeScansUsed"
    private let dateKey = "omr.freeScansDate"
    /// Injected (`shared` uses the app-wide manager) so the gate and the UI share one StoreKitManager.
    let storeKit: any ProEntitlementSource

    private let defaults: UserDefaults
    private let track: @MainActor (String, [String: String]) -> Void

    /// Tests inject `defaults` and `track`; the app uses `UserDefaults.standard` and `Analytics.shared`.
    init(
        storeKit: any ProEntitlementSource,
        defaults: UserDefaults = .standard,
        track: (@MainActor (String, [String: String]) -> Void)? = nil
    ) {
        self.storeKit = storeKit
        self.defaults = defaults
        self.track = track ?? { Analytics.shared.track($0, props: $1) }
    }

    @Published var showPaywall = false

    /// Stored day key: `yyyy-MM-dd` in the Gregorian calendar with the POSIX locale, so changing
    /// Region / Calendar (Buddhist, Japanese, Hijri...) can't change the string and reset the counter
    /// early (P1.8). Cached: building a `DateFormatter` per read is expensive. Main-actor only.
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .autoupdatingCurrent
        return f
    }()

    /// Day key for `date` in `timeZone` (default: the device's current zone, i.e. local midnight rollover).
    static func dayKey(_ date: Date, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        dayFormatter.timeZone = timeZone
        return dayFormatter.string(from: date)
    }

    private var today: String { Self.dayKey(Date()) }

    /// Read-only gate: true if the user may start a scan now. Does NOT consume quota. If false
    /// (free limit reached), tracks the paywall trigger and sets `showPaywall`.
    func canScan() -> Bool {
        if storeKit.isPro { return true }
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
        if storeKit.isPro { return }
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
        if storeKit.isPro { return Int.max }
        let lastDate = defaults.string(forKey: dateKey)
        if lastDate != today { return Self.freeDailyLimit }
        return max(0, Self.freeDailyLimit - defaults.integer(forKey: countKey))
    }
}
