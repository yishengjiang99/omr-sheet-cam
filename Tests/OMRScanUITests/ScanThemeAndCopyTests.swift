import OMRScanKit
import SwiftUI
import XCTest
@testable import OMRScanUI

/// Host seams of the scan UI: theme (environment value), copy (string table override) and the
/// scan-progress → "Reading music… x%" mapping.
@MainActor
final class ScanThemeAndCopyTests: XCTestCase {
    override func tearDown() {
        ScanStrings.hostBundle = .main
        super.tearDown()
    }

    private func pixel(_ image: UIImage, x: Int, y: Int) throws -> [Int] {
        let cg = try XCTUnwrap(image.cgImage)
        var px = [UInt8](repeating: 0, count: 4)
        let ctx = try XCTUnwrap(CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(cg, in: CGRect(x: -x, y: -(cg.height - 1 - y), width: cg.width, height: cg.height))
        return px.prefix(3).map(Int.init)
    }

    func testHostThemeBackgroundRendersInReadingView() throws {
        let theme = ScanTheme(accent: .green, background: Color(red: 0, green: 0.6, blue: 0))
        let view = ReadingView(image: nil, fraction: 0.4, onCancel: {})
            .scanTheme(theme)
            .frame(width: 300, height: 600)
        let r = ImageRenderer(content: view); r.scale = 1
        let img = try XCTUnwrap(r.uiImage)
        let p = try pixel(img, x: 2, y: 300)
        XCTAssertGreaterThan(p[1], 120, "host background (green) is used, not the default near-black")
        XCTAssertLessThan(p[0], 40)
    }

    func testDefaultThemeIsNearBlackCoral() throws {
        let t = ScanTheme.default
        XCTAssertEqual(t.accent, Color(red: 0xEF / 255, green: 0x5A / 255, blue: 0x43 / 255))
        let view = ReadingView(image: nil, onCancel: {}).frame(width: 300, height: 600)
        let r = ImageRenderer(content: view); r.scale = 1
        let p = try pixel(XCTUnwrap(r.uiImage), x: 2, y: 300)
        XCTAssertLessThan(p.max() ?? 255, 40)
    }

    func testStringOverrideFromHostBundleWinsAndMissingKeysFallBack() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("scan-copy-\(UUID().uuidString).bundle")
        let lproj = dir.appendingPathComponent("en.lproj")
        try FileManager.default.createDirectory(at: lproj, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try #"""
        "reading.title.reading" = "Reading the sheet music";
        """#.write(to: lproj.appendingPathComponent("OMRScan.strings"), atomically: true, encoding: .utf8)
        try #"""
        <?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>CFBundleIdentifier</key><string>test.scan.copy</string><key>CFBundleDevelopmentRegion</key><string>en</string></dict></plist>
        """#.write(to: dir.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
        ScanStrings.hostBundle = try XCTUnwrap(Bundle(url: dir))
        XCTAssertEqual(ReadingView.title(fraction: 0.42), "Reading the sheet music… 42%")
        XCTAssertEqual(ReadingView.title(fraction: 0.5, warmingUp: true), "Warming up… 50%", "not overridden: package default")
        ScanStrings.hostBundle = .main
        XCTAssertEqual(ReadingView.title(fraction: 0.42), "Reading music… 42%")
    }

    func testScanStatusMapsToReadingPercentText() {
        let reading = ScanStatus(phase: .reading, fraction: 0.376, page: 0, pageCount: 1)
        XCTAssertEqual(reading.percent, 37)
        XCTAssertEqual(ReadingView.title(fraction: reading.fraction, warmingUp: reading.phase == .warming), "Reading music… 37%")
        let warming = ScanStatus(phase: .warming, fraction: 0.8, etaSeconds: 6, isRewarm: true)
        XCTAssertEqual(ReadingView.title(fraction: warming.fraction, warmingUp: true), "Warming up… 80%")
        XCTAssertEqual(ReadingView.subtitle(warmingUp: true, etaSeconds: 6, isRewarm: true), "About 6 seconds left · reloading the music models")
    }

    func testFlowModelCancelClosesWithoutResultAndNeverCallsHost() async throws {
        final class Host: ScanHost, @unchecked Sendable {
            var finished = 0
            func didFinish(_ result: ScanResult) async throws { finished += 1 }
        }
        struct Slow: RecognitionService {
            func recognize(imageData: Data) async -> RecognitionOutcome {
                await Task.detached { try? await Task.sleep(nanoseconds: 150_000_000) }.value
                return .recognized(RecognitionDetails(midi: Data(), notes: [], staffCount: 1, warnings: [], layoutSource: "x", ms: 1))
            }
        }
        let host = Host()
        var closed: [ScanResult?] = []
        let model = ScanFlowModel(host: host, runner: ScanRunner(service: Slow())) { closed.append($0) }
        let img = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { _ in }
        model.scan([img], source: .fixture)
        XCTAssertEqual(model.phase, .working)
        try await Task.sleep(nanoseconds: 30_000_000)
        model.cancel()
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(closed.count, 1)
        XCTAssertNil(closed[0] ?? nil)
        XCTAssertEqual(host.finished, 0, "a cancelled scan's late result is never handed to the host")
    }
}
