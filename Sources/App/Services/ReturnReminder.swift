import Foundation

/// Gentle, capped upgrade reminder when a free user returns to the app after a few days (P2.9).
/// TODO: stub (legacy behaviour: never any reminder).
@MainActor
final class ReturnReminder: ObservableObject {
    static let shared = ReturnReminder()
    static let minAbsence: TimeInterval = 3 * 86_400
    static let snooze: TimeInterval = 7 * 86_400
    static let lastActiveKey = "omr.lastActiveAt"
    static let notNowKey = "omr.returnNotNowAt"

    @Published private(set) var showBanner = false

    init(defaults: UserDefaults = .standard, clock: @escaping () -> Date = Date.init) {}

    nonisolated static func qualifies(previousActive: Date?, notNowAt: Date?, now: Date) -> Bool { false }

    func appBecameActive(quota: ScanQuota, purchaseInFlight: Bool) {}
    func bannerAppeared(quota: ScanQuota) {}
    func dismiss(quota: ScanQuota) {}
    func seeProTapped(quota: ScanQuota) {}
}
