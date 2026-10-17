import XCTest
@testable import OMRSheetCam

/// P1.6 / P1.10 (counter part): a quiet "N free scans left today" label, a tappable nudge at <= 2,
/// hidden for Pro or while the count is unknown; `ScanQuota.remaining` follows consumption and rollover.
/// Pure logic; also runs on Linux via a scratch SwiftPM harness.
@MainActor
final class ScansLeftTests: XCTestCase {
    private final class FakePro: ProEntitlementSource {
        var isPro = false
        func refreshEntitlements() async {}
    }

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "omr.freeScansUsed")
        UserDefaults.standard.removeObject(forKey: "omr.freeScansDate")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "omr.freeScansUsed")
        UserDefaults.standard.removeObject(forKey: "omr.freeScansDate")
        super.tearDown()
    }

    func testFullQuotaShowsQuietNonTappableLabel() throws {
        let d = try XCTUnwrap(ScansLeft.display(remaining: 5, isPro: false))
        XCTAssertEqual(d.text, "5 free scans left today")
        XCTAssertEqual(d.shortText, "5 left")
        XCTAssertFalse(d.isTappable)
        XCTAssertFalse(try XCTUnwrap(ScansLeft.display(remaining: 3, isPro: false)).isTappable)
    }

    func testTwoOrFewerLeftIsTappable() throws {
        XCTAssertTrue(try XCTUnwrap(ScansLeft.display(remaining: 2, isPro: false)).isTappable)
        let one = try XCTUnwrap(ScansLeft.display(remaining: 1, isPro: false))
        XCTAssertEqual(one.text, "1 free scan left today")
        XCTAssertTrue(one.isTappable)
    }

    func testZeroLeftSaysItResets() throws {
        let d = try XCTUnwrap(ScansLeft.display(remaining: 0, isPro: false))
        XCTAssertEqual(d.text, "0 free scans left - resets tomorrow")
        XCTAssertEqual(d.shortText, "0 left")
        XCTAssertTrue(d.isTappable)
    }

    func testHiddenForProAndWhenUnknown() {
        XCTAssertNil(ScansLeft.display(remaining: 1, isPro: true))
        XCTAssertNil(ScansLeft.display(remaining: nil, isPro: false))
        XCTAssertNil(ScansLeft.display(remaining: Int.max, isPro: true))
    }

    func testRemainingTracksEachConsumedScan() {
        let q = ScanQuota(storeKit: FakePro(), promptPolicy: UpgradePromptPolicy(defaults: UserDefaults(suiteName: UUID().uuidString)!))
        XCTAssertEqual(q.remaining, 5)
        XCTAssertTrue(q.canScan())
        q.commit()
        XCTAssertEqual(q.remaining, 4)
        for _ in 0..<4 { XCTAssertTrue(q.canScan()); q.commit() }
        XCTAssertEqual(q.remaining, 0)
        XCTAssertFalse(q.canScan(), "gate is read-only and blocks at the limit")
        XCTAssertEqual(q.remaining, 0)
    }

    func testRemainingResetsAtDayRollover() {
        UserDefaults.standard.set("2000-01-01", forKey: "omr.freeScansDate")
        UserDefaults.standard.set(5, forKey: "omr.freeScansUsed")
        let q = ScanQuota(storeKit: FakePro(), promptPolicy: UpgradePromptPolicy(defaults: UserDefaults(suiteName: UUID().uuidString)!))
        XCTAssertEqual(q.remaining, 5, "yesterday's usage must not show today")
        UserDefaults.standard.set(2, forKey: "omr.freeScansUsed")
        UserDefaults.standard.set(DateFormatterISO.today(), forKey: "omr.freeScansDate")
        q.refreshRemaining()
        XCTAssertEqual(q.remaining, 3)
    }
}

private enum DateFormatterISO {
    static func today() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
