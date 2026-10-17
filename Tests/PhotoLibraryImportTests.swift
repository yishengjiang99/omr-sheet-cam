import Photos
import XCTest
@testable import OMRSheetCam

/// F4.5: the iCloud PHAsset fallback is only attempted with Photos access the user already granted
/// (the app never requests it); otherwise the user gets an actionable message.
final class PhotoLibraryImportTests: XCTestCase {
    func testAssetFallbackOnlyWithExistingPhotosAccess() {
        XCTAssertTrue(PhotoLibraryImport.canUseAssetFallback(.authorized))
        XCTAssertTrue(PhotoLibraryImport.canUseAssetFallback(.limited))
        for s in [PHAuthorizationStatus.notDetermined, .denied, .restricted] {
            XCTAssertFalse(PhotoLibraryImport.canUseAssetFallback(s), "\(s.rawValue)")
        }
    }

    func testNotDownloadedMessageIsActionable() {
        let msg = PhotoLibraryImport.LoadError.notDownloaded.errorDescription ?? ""
        XCTAssertTrue(msg.contains("iCloud"), msg)
        XCTAssertTrue(msg.contains("Photos"), msg)
        XCTAssertNotEqual(msg, PhotoLibraryImport.LoadError.noData.errorDescription)
        XCTAssertEqual(PhotoLibraryImport.LoadError.notDownloaded.localizedDescription, msg)
    }
}
