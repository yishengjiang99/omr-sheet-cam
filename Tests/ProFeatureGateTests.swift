import XCTest
@testable import OMRSheetCam

/// P9.1: the locked-feature upsell ships behind a feature flag that defaults OFF. With the flag OFF
/// nothing is locked (today's behaviour, matching the paywall copy and review notes). With it ON, free
/// users hit the paywall (reason `feature_<name>`) only for gated features; Pro and saved content never.
@MainActor
final class ProFeatureGateTests: XCTestCase {
    private final class FakePro: ProEntitlementSource {
        var isPro: Bool
        init(pro: Bool) { isPro = pro }
        func refreshEntitlements() async {}
    }

    func testFlagDefaultsOff() {
        let d = UserDefaults(suiteName: UUID().uuidString)!
        XCTAssertFalse(ProFeatureGate.flagEnabled(defaults: d))
        d.set(true, forKey: ProFeatureGate.flagKey)
        XCTAssertTrue(ProFeatureGate.flagEnabled(defaults: d))
    }

    func testFlagOffLocksNothing() {
        for f in ProFeature.allCases {
            XCTAssertTrue(ProFeatureGate.allows(f, isPro: false, flagEnabled: false), "\(f)")
        }
    }

    func testFlagOnLocksGatedFeaturesForFreeUsersOnly() {
        XCTAssertFalse(ProFeatureGate.allows(.transpose, isPro: false, flagEnabled: true))
        XCTAssertTrue(ProFeatureGate.allows(.transpose, isPro: true, flagEnabled: true))
    }

    func testPaywallReasonNamesTheFeature() {
        XCTAssertEqual(ProFeatureGate.paywallReason(for: .transpose), .feature("transpose"))
        XCTAssertEqual(ProFeatureGate.paywallReason(for: .transpose).analyticsValue, "feature_transpose")
    }

    func testLockedTapOpensPaywallWithFeatureReasonAndIsNotCapped() {
        let q = ScanQuota(storeKit: FakePro(pro: false), promptPolicy: UpgradePromptPolicy(defaults: UserDefaults(suiteName: UUID().uuidString)!))
        q.promptDismissed(.postScan) // silenced session: a user tap on a locked control still works
        XCTAssertTrue(q.requestPaywall(ProFeatureGate.paywallReason(for: .transpose)))
        XCTAssertEqual(q.paywallReason, .feature("transpose"))
    }

    func testProIsNeverPromptedForAFeature() {
        let q = ScanQuota(storeKit: FakePro(pro: true), promptPolicy: UpgradePromptPolicy(defaults: UserDefaults(suiteName: UUID().uuidString)!))
        XCTAssertFalse(q.requestPaywall(ProFeatureGate.paywallReason(for: .transpose)))
    }
}
