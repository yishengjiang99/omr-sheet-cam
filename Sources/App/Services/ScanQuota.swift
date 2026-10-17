import Foundation

/// Free tier: 5 scans per day. Pro users have no limit.
@MainActor
final class ScanQuota: ObservableObject {
    static let shared = ScanQuota()
    static let freeDailyLimit = 5

    private let countKey = "omr.freeScansUsed"
    private let dateKey = "omr.freeScansDate"
    private let storeKit = StoreKitManager()

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

    /// Returns true if the user may scan now. If false, caller should show paywall.
    func checkAndConsume() -> Bool {
        if storeKit.isPro { return true }
        let lastDate = UserDefaults.standard.string(forKey: dateKey)
        if lastDate != today {
            UserDefaults.standard.set(today, forKey: dateKey)
            UserDefaults.standard.set(0, forKey: countKey)
        }
        let used = UserDefaults.standard.integer(forKey: countKey)
        if used >= Self.freeDailyLimit {
            Analytics.shared.track("free_quota_hit")
            Analytics.shared.track("paywall_trigger", props: ["reason": "quota"])
            showPaywall = true
            return false
        }
        UserDefaults.standard.set(used + 1, forKey: countKey)
        return true
    }

    var scansRemaining: Int {
        if storeKit.isPro { return Int.max }
        let lastDate = UserDefaults.standard.string(forKey: dateKey)
        if lastDate != today { return Self.freeDailyLimit }
        return max(0, Self.freeDailyLimit - UserDefaults.standard.integer(forKey: countKey))
    }
}
