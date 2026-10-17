import UIKit
import XCTest
@testable import OMRSheetCam

/// F5.5: "Retake" on the Result screen lands on the live Camera for camera photos (Library for
/// Photos / sample picks), instead of always popping to the Library.
final class RetakeRouteTests: XCTestCase {
    private func photo(_ source: CapturedPhoto.Source) -> CapturedPhoto {
        CapturedPhoto(image: UIImage(), source: source)
    }

    func testRetakeCameraPhotoReopensCamera() {
        let p = photo(.camera)
        // handlePhoto removes .camera before pushing .result, so the stack is [result] over Library.
        XCTAssertEqual(RootFlowView.pathAfterRetake([.result(p)], photo: p), [.camera])
    }

    func testRetakeLibraryAndSamplePhotoReturnsToLibrary() {
        for source in [CapturedPhoto.Source.library, .sample] {
            let p = photo(source)
            XCTAssertEqual(RootFlowView.pathAfterRetake([.result(p)], photo: p), [], "\(source)")
        }
    }

    func testRetakeOnlyDropsTheResultAndWhatIsAboveIt() {
        let a = photo(.camera), b = photo(.camera)
        XCTAssertEqual(RootFlowView.pathAfterRetake([.result(a), .result(b)], photo: b), [.result(a), .camera])
        XCTAssertEqual(RootFlowView.pathAfterRetake([.result(a), .camera], photo: a), [.camera], "everything above the result is dropped")
        // Unknown photo (already popped): nothing removed; a camera photo still gets the Camera.
        XCTAssertEqual(RootFlowView.pathAfterRetake([], photo: a), [.camera])
    }
}
