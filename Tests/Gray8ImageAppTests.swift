import ImageIO
import OMRHomrIOS
import XCTest
@testable import OMRSheetCam
@testable import OMRScanKit

final class Gray8ImageAppTests: XCTestCase {
    /// App decoder (ImageIO + CGContext) vs the package's homr-exact PNG decoder (`cv2.imread` +
    /// `BGR2GRAY`) on every oracle page input: same size, every byte within 1 gray level.
    func testMatchesPackagePNGDecoderOnOraclePageInputs() throws {
        let pages = try PageRecognitionAppTests.oraclePages()
        guard !pages.isEmpty else { throw XCTSkip("no fixtures/oracle.pages") }
        for page in pages {
            let data = try Data(contentsOf: page.input)
            let app = try Gray8Image.decode(imageData: data)
            let ref = try PagePipeline.decodeGrayPNG(data)
            XCTAssertEqual([app.width, app.height], [ref.width, ref.height], page.id)
            XCTAssertEqual(app.pixels.count, ref.pixels.count, page.id)
            guard app.pixels.count == ref.pixels.count else { continue }
            var maxDiff = 0, differing = 0
            app.pixels.withUnsafeBytes { a in
                for i in 0..<ref.pixels.count {
                    let d = abs(Int(a[i]) - Int(ref.pixels[i]))
                    if d > 0 { differing += 1; maxDiff = max(maxDiff, d) }
                }
            }
            print("Gray8 parity \(page.id): \(app.width)x\(app.height) \(app.source) · differing \(differing) · max |diff| \(maxDiff)")
            XCTAssertLessThanOrEqual(maxDiff, 1, "\(page.id): \(differing) px differ, max \(maxDiff) (\(app.source))")
        }
    }
}
