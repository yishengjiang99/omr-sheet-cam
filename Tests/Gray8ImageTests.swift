import ImageIO
import OMRHomrIOS
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import OMRSheetCam

/// App-side gray8 decoder: EXIF orientation → upright, `bytesPerRow == width` (no padding).
final class Gray8ImageTests: XCTestCase {
    /// White `w x h` DeviceGray image with one black pixel at raw `(x, y)` (y down).
    private func grayImage(w: Int, h: Int, dark: (x: Int, y: Int)) -> CGImage {
        var bytes = [UInt8](repeating: 255, count: w * h)
        bytes[dark.y * w + dark.x] = 0
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(
            width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
    }

    private func darkPixels(_ g: Gray8Image) -> [[Int]] {
        var out: [[Int]] = []
        for y in 0..<g.height { for x in 0..<g.width where g[x, y] < 128 { out.append([x, y]) } }
        return out
    }

    func testOddWidthHasNoRowPaddingAndKeepsKnownPixel() throws {
        let g = try Gray8Image.from(cgImage: grayImage(w: 13, h: 7, dark: (5, 2)), orientation: .up)
        XCTAssertEqual(g.width, 13)
        XCTAssertEqual(g.height, 7)
        XCTAssertEqual(g.pixels.count, 13 * 7, "bytesPerRow must equal width")
        XCTAssertLessThan(g.pixels[2 * 13 + 5], 30)
        XCTAssertEqual(darkPixels(g), [[5, 2]])
        XCTAssertGreaterThan(g[0, 0], 225)
    }

    /// Raw 5x3, dark pixel at raw (1, 0); expected upright position per EXIF orientation.
    func testAllEXIFOrientations() throws {
        let w = 5, h = 3
        let cases: [(CGImagePropertyOrientation, Int, Int, [Int])] = [
            (.up, 5, 3, [1, 0]),
            (.upMirrored, 5, 3, [3, 0]),
            (.down, 5, 3, [3, 2]),
            (.downMirrored, 5, 3, [1, 2]),
            (.leftMirrored, 3, 5, [0, 1]),
            (.right, 3, 5, [2, 1]),
            (.rightMirrored, 3, 5, [2, 3]),
            (.left, 3, 5, [0, 3]),
        ]
        let img = grayImage(w: w, h: h, dark: (1, 0))
        for (o, ew, eh, pos) in cases {
            let g = try Gray8Image.from(cgImage: img, orientation: o)
            XCTAssertEqual(g.width, ew, "\(o.rawValue) width")
            XCTAssertEqual(g.height, eh, "\(o.rawValue) height")
            XCTAssertEqual(g.pixels.count, ew * eh, "\(o.rawValue) no padding")
            XCTAssertEqual(darkPixels(g), [pos], "orientation \(o.rawValue)")
        }
    }

    func testUIImageOrientationIsApplied() throws {
        let img = UIImage(cgImage: grayImage(w: 5, h: 3, dark: (1, 0)), scale: 1, orientation: .left)
        let g = try Gray8Image.from(img)
        XCTAssertEqual([g.width, g.height], [3, 5])
        XCTAssertEqual(darkPixels(g), [[0, 3]])
    }

    /// JPEG bytes carrying EXIF orientation 6 (.right): 40x20 raw, left half black → upright 20x40, black on top.
    func testDecodeEncodedJPEGHonorsEXIFOrientation() throws {
        var bytes = [UInt8](repeating: 255, count: 40 * 20)
        for y in 0..<20 { for x in 0..<20 { bytes[y * 40 + x] = 0 } }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let cg = CGImage(
            width: 40, height: 20, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: 40,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
        let data = NSMutableData()
        let dest = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, cg, [kCGImagePropertyOrientation: 6, kCGImageDestinationLossyCompressionQuality: 1.0] as [CFString: Any] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))

        let g = try Gray8Image.decode(imageData: data as Data)
        XCTAssertEqual([g.width, g.height], [20, 40])
        XCTAssertEqual(g.pixels.count, 20 * 40)
        XCTAssertLessThan(g[10, 5], 60, "raw left half must end up on top")
        XCTAssertGreaterThan(g[10, 35], 195)
    }

    func testRGBImageBecomesGray() throws {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: 9, height: 4), format: format).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 9, height: 4))
            UIColor.black.setFill(); ctx.fill(CGRect(x: 8, y: 3, width: 1, height: 1))
        }
        let g = try Gray8Image.from(img)
        XCTAssertEqual([g.width, g.height, g.pixels.count], [9, 4, 36])
        XCTAssertEqual(darkPixels(g), [[8, 3]])
    }

    /// App decoder (ImageIO + CGContext) vs the package's homr-exact PNG decoder (`cv2.imread` +
    /// `BGR2GRAY`) on every oracle page input: same size, every byte within 1 gray level.
    func testMatchesPackagePNGDecoderOnOraclePageInputs() throws {
        let pages = try PageRecognitionServiceTests.oraclePages()
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

    func testUndecodableDataThrows() {
        XCTAssertThrowsError(try Gray8Image.decode(imageData: Data()))
        XCTAssertThrowsError(try Gray8Image.decode(imageData: Data([0x01, 0x02, 0x03, 0x04])))
    }
}
