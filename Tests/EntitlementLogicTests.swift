import XCTest
@testable import OMRSheetCam

/// Stream A (IAP audit) P7.4 / P7.6: Pro is derived from the current entitlement list (and re-checked
/// before each scan), not patched per transaction or cached once per launch. Pure logic: no StoreKit
/// session needed (also runs on Linux via a scratch SwiftPM harness).
@MainActor
final class EntitlementLogicTests: XCTestCase {
    private let ids = Set([IAPProductID.monthly, IAPProductID.yearly])

    private func snap(
        _ id: String, tx: UInt64 = 1, revoked: Bool = false, upgraded: Bool = false
    ) -> EntitlementSnapshot {
        EntitlementSnapshot(
            productID: id, transactionID: tx,
            revocationDate: revoked ? Date(timeIntervalSince1970: 1_800_000_000) : nil,
            isUpgraded: upgraded)
    }

    // MARK: derive from the current list

    func testSupersededUpgradedTransactionDoesNotGrantPro() {
        XCTAssertFalse(EntitlementLogic.isPro(entitlements: [snap(IAPProductID.monthly, upgraded: true)], validIDs: ids))
    }

    func testActiveEntitlementGrantsPro() {
        XCTAssertTrue(EntitlementLogic.isPro(entitlements: [snap(IAPProductID.yearly)], validIDs: ids))
        XCTAssertFalse(EntitlementLogic.isPro(entitlements: [], validIDs: ids))
    }

    func testUnknownProductNeverGrantsPro() {
        XCTAssertFalse(EntitlementLogic.isPro(entitlements: [snap("com.example.other")], validIDs: ids))
    }

    func testMultipleEntitlementsAreAllReported() {
        let active = EntitlementLogic.activeEntitlements(
            [snap(IAPProductID.yearly, tx: 1), snap(IAPProductID.monthly, tx: 2), snap(IAPProductID.monthly, tx: 3, revoked: true)],
            validIDs: ids)
        XCTAssertEqual(active.map(\.transactionID), [1, 2])
    }

    // MARK: P7.6 revoke / replay delivered via Transaction.updates

    func testRevokingOneEntitlementKeepsProWhileAnotherIsValid() {
        let pro = EntitlementLogic.proAfterUpdate(
            current: true,
            update: snap(IAPProductID.monthly, tx: 2, revoked: true),
            entitlements: [snap(IAPProductID.yearly, tx: 1)],
            validIDs: ids)
        XCTAssertTrue(pro, "refunding monthly must not lock Pro while yearly is still valid")
    }

    func testRevokingTheLastEntitlementLocksPro() {
        let pro = EntitlementLogic.proAfterUpdate(
            current: true, update: snap(IAPProductID.yearly, revoked: true), entitlements: [], validIDs: ids)
        XCTAssertFalse(pro)
    }

    func testReplayedExpiredTransactionDoesNotGrantPro() {
        // An expired transaction is delivered again (revocationDate nil) but is no longer a current entitlement.
        let pro = EntitlementLogic.proAfterUpdate(
            current: false, update: snap(IAPProductID.monthly), entitlements: [], validIDs: ids)
        XCTAssertFalse(pro, "an expired transaction delivered by Transaction.updates must not grant Pro")
    }

    func testValidNewTransactionGrantsPro() {
        let t = snap(IAPProductID.monthly)
        XCTAssertTrue(EntitlementLogic.proAfterUpdate(current: false, update: t, entitlements: [t], validIDs: ids))
    }

    func testUpdateForUnrelatedProductLeavesStateAlone() {
        XCTAssertTrue(EntitlementLogic.proAfterUpdate(
            current: true, update: snap("com.example.other", revoked: true), entitlements: [], validIDs: ids))
    }

    // MARK: P7.4 the scan gate re-checks before consuming

    @MainActor
    private final class FakeEntitlements: ProEntitlementSource {
        var isPro: Bool
        let proAfterRefresh: Bool
        private(set) var refreshCount = 0
        init(isPro: Bool, proAfterRefresh: Bool) { self.isPro = isPro; self.proAfterRefresh = proAfterRefresh }
        func refreshEntitlements() async { refreshCount += 1; isPro = proAfterRefresh }
    }

    private func resetQuota(used: Int) {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        UserDefaults.standard.set(f.string(from: Date()), forKey: "omr.freeScansDate")
        UserDefaults.standard.set(used, forKey: "omr.freeScansUsed")
        addTeardownBlock {
            UserDefaults.standard.removeObject(forKey: "omr.freeScansDate")
            UserDefaults.standard.removeObject(forKey: "omr.freeScansUsed")
        }
    }

    func testGateRefreshesEntitlementsBeforeConsuming_lapsedProGetsPaywall() async {
        resetQuota(used: ScanQuota.freeDailyLimit)
        let fake = FakeEntitlements(isPro: true, proAfterRefresh: false) // stale cached Pro, lapsed in the store
        let quota = ScanQuota(storeKit: fake)
        let ok = await quota.admitScan()
        XCTAssertFalse(ok, "lapsed Pro must hit the quota wall on the next scan, without relaunch")
        XCTAssertTrue(quota.showPaywall)
        XCTAssertEqual(fake.refreshCount, 1)
    }

    func testGateStillAdmitsProAfterRefresh() async {
        resetQuota(used: ScanQuota.freeDailyLimit)
        let fake = FakeEntitlements(isPro: false, proAfterRefresh: true) // renewed while backgrounded
        let quota = ScanQuota(storeKit: fake)
        let ok = await quota.admitScan()
        XCTAssertTrue(ok, "a renewed Pro user with a stale lapsed cache must not see the paywall")
        XCTAssertFalse(quota.showPaywall)
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "omr.freeScansUsed"), ScanQuota.freeDailyLimit)
    }

    func testGateFreeUserConsumesQuotaThenBlocks() async {
        resetQuota(used: ScanQuota.freeDailyLimit - 1)
        let quota = ScanQuota(storeKit: FakeEntitlements(isPro: false, proAfterRefresh: false))
        let first = await quota.admitScan()
        let second = await quota.admitScan()
        XCTAssertTrue(first)
        XCTAssertFalse(second)
        XCTAssertTrue(quota.showPaywall)
    }
}
