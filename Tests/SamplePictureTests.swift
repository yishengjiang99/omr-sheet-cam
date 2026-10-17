import UIKit
import XCTest
@testable import OMRSheetCam

/// F4.7: the Library's "Try sample picture" surfaces a load failure (same message as the Camera
/// screen) instead of only writing to the diagnostics log.
final class SamplePictureTests: XCTestCase {
    private struct Missing: Error {}

    @MainActor
    func testLoadFailureReturnsUserVisibleMessageAndLogs() async {
        let log = DiagnosticsLog(directory: nil, mirrorToOSLog: false)
        let r = await SamplePicture.loadForUser(context: "Try sample picture (library)", loader: { throw Missing() }, log: log)
        XCTAssertNil(r.photo)
        XCTAssertEqual(r.error, "Could not load the sample picture", "must be shown to the user, not only logged")
        XCTAssertEqual(r.error, SamplePicture.loadFailedMessage)
        XCTAssertTrue(log.events.contains { $0.category == .capture && $0.level == .error })
    }

    @MainActor
    func testLoadSuccessReturnsPhotoWithoutError() async {
        let log = DiagnosticsLog(directory: nil, mirrorToOSLog: false)
        let photo = CapturedPhoto(image: UIImage(), source: .sample)
        let r = await SamplePicture.loadForUser(context: "Try sample picture (library)", loader: { photo }, log: log)
        XCTAssertEqual(r.photo, photo)
        XCTAssertNil(r.error)
        XCTAssertFalse(log.events.contains { $0.level == .error })
    }
}
