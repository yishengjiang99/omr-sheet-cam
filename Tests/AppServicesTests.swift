import XCTest
@testable import OMRSheetCam
@testable import OMRScanKit

final class AppServicesTests: XCTestCase {
    func testStubRecognitionReturnsComingSoon() async {
        let outcome = await StubRecognitionService().recognize(imageData: Data([0xFF, 0xD8]))
        XCTAssertEqual(outcome, .comingSoon)
        XCTAssertTrue(AppServices.recognition is PageRecognitionService)
    }

    func testSampleMIDIIsValidSMF() throws {
        let midi = try SampleMIDI.cMajorScale()
        XCTAssertEqual(Array(midi.prefix(4)), Array("MThd".utf8))
        XCTAssertGreaterThan(midi.count, 14)
    }
}
