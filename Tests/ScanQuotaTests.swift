import XCTest
@testable import OMRSheetCam

/// P1.4: the free daily scan is charged only when recognition succeeds (`canScan()` is a read-only
/// gate, `commit()` records the use). Failed / cancelled / reader-not-ready scans never commit.
final class ScanQuotaTests: XCTestCase {
    @MainActor
    private final class FakePro: ProEntitlementSource {
        var isPro: Bool
        init(_ isPro: Bool) { self.isPro = isPro }
        func refreshEntitlements() async {}
    }

    /// Isolated UserDefaults suite + captured analytics events for one test.
    @MainActor
    private final class Env {
        let suite = "ScanQuotaTests-\(UUID().uuidString)"
        let defaults: UserDefaults
        var events: [String] = []

        init() { defaults = UserDefaults(suiteName: suite)! }

        var used: Int { defaults.integer(forKey: "omr.freeScansUsed") }

        func quota(pro: Bool = false) -> ScanQuota {
            ScanQuota(storeKit: FakePro(pro), defaults: defaults, track: { [self] name, _ in events.append(name) })
        }
    }

    @MainActor
    private func makeEnv() -> Env {
        let env = Env()
        addTeardownBlock { @MainActor in env.defaults.removePersistentDomain(forName: env.suite) }
        return env
    }

    @MainActor
    private static func recognized() -> RecognitionOutcome {
        .recognized(RecognitionDetails(midi: Data("MThd".utf8), notes: [], staffCount: 1, warnings: [], layoutSource: "midiFallback", ms: 1))
    }

    @MainActor
    func testCanScanDoesNotConsume() {
        let env = makeEnv()
        let q = env.quota()
        for _ in 0..<10 { XCTAssertTrue(q.canScan()) }
        XCTAssertEqual(env.used, 0, "the gate must not charge a scan")
        XCTAssertEqual(q.scansRemaining, ScanQuota.freeDailyLimit)
        XCTAssertFalse(q.showPaywall)
    }

    @MainActor
    func testCommitChargesOneAndSixthScanIsBlocked() {
        let env = makeEnv()
        let q = env.quota()
        for n in 1...ScanQuota.freeDailyLimit {
            XCTAssertTrue(q.canScan(), "scan \(n) must be allowed")
            q.commit()
            XCTAssertEqual(env.used, n)
        }
        XCTAssertEqual(q.scansRemaining, 0)
        XCTAssertFalse(q.canScan(), "6th scan must be blocked")
        XCTAssertTrue(q.showPaywall)
        XCTAssertEqual(env.events, ["free_quota_hit", "paywall_trigger"])
        XCTAssertEqual(env.used, ScanQuota.freeDailyLimit, "a blocked check must not change the counter")
    }

    @MainActor
    func testFailedAndCancelledScansNeverReachTheLimit() {
        let env = makeEnv()
        let q = env.quota()
        var commits = 0
        // 20 scans that fail / are cancelled (no commit) must never lock the user out.
        for _ in 0..<20 {
            XCTAssertTrue(q.canScan())
            ResultScreen.commitQuotaIfRecognized(.failed("no music staff found"), commit: { commits += 1; q.commit() })
            ResultScreen.commitQuotaIfRecognized(.failed("cancelled"), commit: { commits += 1; q.commit() })
            ResultScreen.commitQuotaIfRecognized(.comingSoon, commit: { commits += 1; q.commit() })
        }
        XCTAssertEqual(commits, 0)
        XCTAssertEqual(env.used, 0)
        XCTAssertFalse(q.showPaywall)
    }

    @MainActor
    func testRecognizedOutcomeCommitsExactlyOnce() {
        let env = makeEnv()
        let q = env.quota()
        ResultScreen.commitQuotaIfRecognized(Self.recognized(), commit: { q.commit() })
        XCTAssertEqual(env.used, 1)
        XCTAssertEqual(q.scansRemaining, ScanQuota.freeDailyLimit - 1)
    }

    @MainActor
    func testProIsNeverChargedOrBlocked() {
        let env = makeEnv()
        let q = env.quota(pro: true)
        for _ in 0..<10 { XCTAssertTrue(q.canScan()); q.commit() }
        XCTAssertEqual(env.used, 0)
        XCTAssertEqual(q.scansRemaining, Int.max)
        XCTAssertFalse(q.showPaywall)
    }

    @MainActor
    func testNewDayResetsCounter() {
        let env = makeEnv()
        let defaults = env.defaults
        defaults.set("2000-01-01", forKey: "omr.freeScansDate")
        defaults.set(ScanQuota.freeDailyLimit, forKey: "omr.freeScansUsed")
        let q = env.quota()
        XCTAssertEqual(q.scansRemaining, ScanQuota.freeDailyLimit)
        XCTAssertTrue(q.canScan())
        XCTAssertEqual(env.used, 0, "rollover resets to 0; the gate itself charges nothing")
        q.commit()
        XCTAssertEqual(env.used, 1)
    }
}
