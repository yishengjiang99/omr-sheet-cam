import UIKit
import XCTest
@testable import OMRSheetCam

/// Capture helpers only (no camera hardware): EXIF orientation normalization, JPEG saving,
/// the RecognitionService stub and the bundled Play-sample MIDI.
final class CaptureHelpersTests: XCTestCase {
    /// 40×20 landscape pixels: left half red, right half blue.
    private func makeCGImage() -> CGImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 40, height: 20), format: format).image { ctx in
            UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
            UIColor.blue.setFill(); ctx.fill(CGRect(x: 20, y: 0, width: 20, height: 20))
        }.cgImage!
    }

    func testNormalizeRightOrientedImageIsUprightPortrait() throws {
        let rotated = UIImage(cgImage: makeCGImage(), scale: 1, orientation: .right)
        XCTAssertEqual(rotated.size, CGSize(width: 20, height: 40)) // displayed size already rotated
        let up = CaptureStore.normalizedUpright(rotated)
        XCTAssertEqual(up.imageOrientation, .up)
        XCTAssertEqual(up.size, CGSize(width: 20, height: 40))
        let cg = try XCTUnwrap(up.cgImage)
        XCTAssertEqual(cg.width, 20)
        XCTAssertEqual(cg.height, 40)
        // .right = rotate 90° clockwise: the source's left (red) half ends up on top.
        XCTAssertEqual(try pixelIsRed(cg, x: 10, y: 5), true)
        XCTAssertEqual(try pixelIsRed(cg, x: 10, y: 35), false)
    }

    func testNormalizeUpImageIsUnchanged() {
        let img = UIImage(cgImage: makeCGImage(), scale: 1, orientation: .up)
        XCTAssertTrue(CaptureStore.normalizedUpright(img) === img)
    }

    func testSaveWritesUprightJPEGWithTimestampName() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("captures-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let img = UIImage(cgImage: makeCGImage(), scale: 1, orientation: .left)
        let url = try CaptureStore.save(img, date: date, directory: dir)
        XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL, dir.standardizedFileURL)
        XCTAssertEqual(url.lastPathComponent, "\(CaptureStore.timestamp(date)).jpg")
        XCTAssertNotNil(url.lastPathComponent.range(of: #"^\d{8}-\d{6}-\d{3}\.jpg$"#, options: .regularExpression))
        let data = try Data(contentsOf: url)
        XCTAssertEqual(Array(data.prefix(2)), [0xFF, 0xD8], "JPEG SOI")
        let back = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(back.imageOrientation, .up)
        XCTAssertEqual(back.size, CGSize(width: 20, height: 40))
        // Same timestamp again: no overwrite.
        let second = try CaptureStore.save(img, date: date, directory: dir)
        XCTAssertNotEqual(second, url)
        XCTAssertEqual(second.lastPathComponent, "\(CaptureStore.timestamp(date))-1.jpg")
    }

    func testDefaultDirectoryIsDocumentsCaptures() throws {
        let dir = try CaptureStore.defaultDirectory()
        XCTAssertEqual(dir.lastPathComponent, "captures")
        XCTAssertEqual(dir.deletingLastPathComponent().lastPathComponent, "Documents")
    }

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

    private func pixelIsRed(_ cg: CGImage, x: Int, y: Int) throws -> Bool {
        var px = [UInt8](repeating: 0, count: 4)
        let ctx = try XCTUnwrap(CGContext(
            data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        ctx.draw(cg, in: CGRect(x: -x, y: -(cg.height - 1 - y), width: cg.width, height: cg.height))
        return px[0] > 200 && px[2] < 60
    }
}
