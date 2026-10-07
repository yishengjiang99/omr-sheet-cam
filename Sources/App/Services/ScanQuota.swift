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

    private var today: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

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
