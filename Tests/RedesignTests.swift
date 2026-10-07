import XCTest
@testable import OMRSheetCam

/// Settings → About → "Source code & license" (AGPL-3.0) and its bundled texts.
final class RedesignTests: XCTestCase {
    @MainActor
    func testSourceCodeAndLicenseRowExists() {
        XCTAssertTrue(SettingsView.aboutRows.contains(.sourceCode))
        XCTAssertEqual(SettingsView.title(.sourceCode), "Source code & license")
        XCTAssertTrue(SettingsView.sections(developerEnabled: false).contains(.about))
        XCTAssertEqual(SettingsView.repoURL.absoluteString, "https://github.com/yishengjiang99/omr-sheet-cam")
    }

    @MainActor
    func testLicenseTextsAreBundled() {
        XCTAssertTrue(LicenseTexts.license().contains("GNU AFFERO GENERAL PUBLIC LICENSE"))
        let notice = NoticeParser.entries(LicenseTexts.notice())
        XCTAssertTrue(notice.contains { $0.title.contains("ONNX Runtime") })
        XCTAssertTrue(LicenseTexts.resource("ONNXRuntime-ThirdPartyNotices").contains("protobuf"))
    }

    @MainActor
    func testLibraryHomeHowItWorksArtExists() {
        XCTAssertEqual(SamplePicture.buttonTitle, "Try sample picture")
        _ = HowItWorksArt()
    }

    func testLegacyRecognitionGateKeyConstant() {
        XCTAssertEqual(AppServices.legacyExperimentalRecognitionKey, "developer.experimentalPageRecognition")
    }
}
