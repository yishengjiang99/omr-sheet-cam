import XCTest
@testable import OMRSheetCam

/// P11.1: the App Review notes must be executable against the app as shipped. The Library's
/// "Try sample picture" only shows while the Library is empty (first scan); the Camera screen
/// always has it. The notes are read from the repo (docs/asc/metadata/review_information/notes.txt).
final class ReviewNotesTests: XCTestCase {
    private func notes() throws -> String {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: repo.appendingPathComponent("docs/asc/metadata/review_information/notes.txt"), encoding: .utf8)
    }

    func testNotesNameTheSampleButtonExactlyAsTheAppDoes() throws {
        XCTAssertTrue(try notes().contains("\"\(SamplePicture.buttonTitle)\""), "notes must quote the button title: \(SamplePicture.buttonTitle)")
    }

    /// Scans 2...6 can't start from the Library's sample button (it disappears once a scan is saved),
    /// so the notes must send the reviewer through the Camera screen (or Photos import).
    func testNotesGiveAPathForRepeatScansViaCameraScreen() throws {
        let n = try notes()
        XCTAssertTrue(n.contains("\"Camera\""), "notes must tell the reviewer to open Camera for repeat scans")
        XCTAssertTrue(n.localizedCaseInsensitiveContains("Camera screen"), "notes must say the sample button is on the Camera screen")
        XCTAssertTrue(n.localizedCaseInsensitiveContains("empty"), "notes must explain the Library button shows only while the Library is empty")
    }

    func testNotesDoNotPromiseARepeatableLibrarySampleButton() throws {
        let n = try notes()
        XCTAssertFalse(n.contains("on the Library home screen tap \"Try sample picture\" (or scan / import any sheet-music photo), go back and repeat"),
                       "old wording: the Library button is gone after the first saved scan")
    }

    func testNotesFitAppStoreConnectLimitAndKeepPaywallFacts() throws {
        let n = try notes()
        XCTAssertLessThanOrEqual(n.count, 4000, "ASC review notes limit is 4000 characters")
        XCTAssertTrue(n.contains("\(ScanQuota.freeDailyLimit) page scans per day"), "free limit in notes must match ScanQuota.freeDailyLimit")
        XCTAssertTrue(n.contains(IAPProductID.monthly) && n.contains(IAPProductID.yearly))
        XCTAssertTrue(n.contains("6th scan"), "6th scan = first over the free limit")
    }
}
