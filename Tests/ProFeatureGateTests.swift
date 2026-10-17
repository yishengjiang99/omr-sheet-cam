import XCTest
@testable import OMRSheetCam

/// P9.1: the locked-feature upsell is always on (product decision by Yisheng, no feature flag). Free
/// users who try a gated feature (Transpose) get the soft, dismissible paywall with reason
/// `feature_transpose`; Pro users and every other feature are never affected.
@MainActor
final class ProFeatureGateTests: XCTestCase {
    private final class FakePro: ProEntitlementSource {
        var isPro: Bool
        init(pro: Bool) { isPro = pro }
        func refreshEntitlements() async {}
    }

    private func quota(pro: Bool) -> ScanQuota {
        ScanQuota(storeKit: FakePro(pro: pro), promptPolicy: UpgradePromptPolicy(defaults: UserDefaults(suiteName: UUID().uuidString)!))
    }

    func testTransposeIsLockedForFreeUsers() {
        XCTAssertFalse(ProFeatureGate.allows(.transpose, isPro: false))
    }

    func testProUsersAreNeverLocked() {
        for f in ProFeature.allCases {
            XCTAssertTrue(ProFeatureGate.allows(f, isPro: true), "\(f)")
        }
    }

    func testOnlyTransposeIsGated() {
        XCTAssertEqual(ProFeatureGate.gated, [.transpose])
        XCTAssertEqual(ProFeature.allCases, [.transpose])
    }

    func testNoFeatureFlagRemains() {
        // The gate has no switch: nothing reads a UserDefaults flag, so a stale key cannot unlock it.
        UserDefaults.standard.set(false, forKey: "omr.flag.lockedFeatures")
        defer { UserDefaults.standard.removeObject(forKey: "omr.flag.lockedFeatures") }
        XCTAssertFalse(ProFeatureGate.allows(.transpose, isPro: false))
    }

    func testPaywallReasonNamesTheFeature() {
        XCTAssertEqual(ProFeatureGate.paywallReason(for: .transpose), .feature("transpose"))
        XCTAssertEqual(ProFeatureGate.paywallReason(for: .transpose).analyticsValue, "feature_transpose")
    }

    func testLockedTapOpensPaywallWithFeatureReasonAndIsNotCapped() {
        let q = quota(pro: false)
        q.promptDismissed(.postScan) // silenced session: a user tap on a locked control still works
        XCTAssertTrue(q.requestPaywall(ProFeatureGate.paywallReason(for: .transpose)))
        XCTAssertEqual(q.paywallReason, .feature("transpose"))
    }

    func testProIsNeverPromptedForAFeature() {
        XCTAssertFalse(quota(pro: true).requestPaywall(ProFeatureGate.paywallReason(for: .transpose)))
    }

    /// Paywall copy must list every gated feature as Pro, and quote the real free limit.
    func testPaywallCopyListsTransposeAsProAndMatchesFreeLimit() {
        XCTAssertTrue(ProFeatureGate.gated.contains(.transpose))
        XCTAssertTrue(PaywallCopy.intro.contains("Transpose"))
        XCTAssertTrue(PaywallCopy.proRows.contains { $0.localizedCaseInsensitiveContains("Transpose") })
        XCTAssertTrue(PaywallCopy.intro.contains("\(ScanQuota.freeDailyLimit) page scans"))
        XCTAssertTrue(PaywallCopy.proRows.contains("Unlimited scans"))
    }
}
