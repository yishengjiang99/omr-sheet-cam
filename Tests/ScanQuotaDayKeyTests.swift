import XCTest
@testable import OMRSheetCam

/// P1.8: the quota's stored day key is calendar/locale independent (`yyyy-MM-dd`, Gregorian, POSIX).
@MainActor
final class ScanQuotaDayKeyTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private let la = TimeZone(identifier: "America/Los_Angeles")!

    /// 2026-10-17 12:00:00 UTC
    private let noon = Date(timeIntervalSince1970: 1_792_238_400)

    func testKeyIsGregorianYyyyMmDd() {
        XCTAssertEqual(ScanQuota.dayKey(noon, timeZone: utc), "2026-10-17")
    }

    /// The same instant must always give the same key, even when the user's calendar is not Gregorian
    /// (an unpinned formatter would give 2569-10-17 under the Buddhist calendar, 8-digit Hijri years, ...).
    func testKeyIgnoresDeviceCalendarAndLocale() {
        let buddhist = DateFormatter()
        buddhist.locale = Locale(identifier: "th_TH@calendar=buddhist")
        buddhist.dateFormat = "yyyy-MM-dd"
        buddhist.timeZone = utc
        XCTAssertEqual(buddhist.string(from: noon), "2569-10-17", "precondition: an unpinned formatter drifts with the calendar")
        XCTAssertEqual(ScanQuota.dayKey(noon, timeZone: utc), "2026-10-17")
    }

    func testRollsOverAtLocalMidnight() {
        // 2026-10-17 23:59:59 PDT = 06:59:59 UTC on the 18th; one second later it is the 18th locally.
        let before = Date(timeIntervalSince1970: 1_792_306_799)
        let after = before.addingTimeInterval(1)
        XCTAssertEqual(ScanQuota.dayKey(before, timeZone: la), "2026-10-17")
        XCTAssertEqual(ScanQuota.dayKey(after, timeZone: la), "2026-10-18")
        XCTAssertEqual(ScanQuota.dayKey(before, timeZone: utc), "2026-10-18", "UTC is already on the 18th")
    }
}
