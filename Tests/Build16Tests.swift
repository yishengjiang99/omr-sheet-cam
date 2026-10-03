import SwiftUI
import UIKit
import XCTest
@testable import OMRSheetCam

/// Build 16 work: public-domain sample, Dark Mode surfaces, failed-scan reasons, share/transpose,
/// note highlighting, A–B loop and per-hand mute.
final class Build16Tests: XCTestCase {
    // MARK: - Sample + Dark Mode

    @MainActor
    func testPlaySampleIsPublicDomainOdeToJoy() throws {
        let keys = PlaylistSample.bundled.map(\.key)
        XCTAssertEqual(keys.first, SampleMIDI.odeToJoyKey)
        XCTAssertFalse(keys.contains { $0.lowercased().contains("swe") })
        XCTAssertNil(Bundle.main.url(forResource: "sweden", withExtension: "midi"), "old sample must not ship")
        XCTAssertGreaterThan(try SampleMIDI.odeToJoy().count, 100)
    }

    /// Player / Library surfaces must be dark in Dark Mode so `.primary` (white) text stays readable.
    func testThemeSurfacesFollowDarkMode() {
        for c in [Theme.cream, Theme.coralSoft] {
            let ui = UIColor(c)
            let light = Self.luminance(ui.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)))
            let dark = Self.luminance(ui.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)))
            let labelDark = Self.luminance(UIColor.label.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)))
            let labelLight = Self.luminance(UIColor.label.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)))
            XCTAssertGreaterThan(light, 0.8)
            XCTAssertLessThan(dark, 0.05)
            XCTAssertGreaterThan(Self.contrast(labelDark, dark), 7, "white text on dark surface")
            XCTAssertGreaterThan(Self.contrast(labelLight, light), 7, "black text on light surface")
        }
    }

    // MARK: - Failed scans

    func testScanFailureClassifiesPipelineMessages() {
        XCTAssertEqual(ScanFailure.classify("page staff detection: no noteheads found (homr: 'No noteheads found')"), .noMusicFound)
        XCTAssertEqual(ScanFailure.classify("page staff detection: no staffs found"), .noStaffFound)
        XCTAssertEqual(ScanFailure.classify("no music staff found on the page (staffCount 0)"), .noStaffFound)
        XCTAssertEqual(ScanFailure.classify("no notes recognized (2 staffs)"), .noNotesFound(staffCount: 2))
        XCTAssertEqual(ScanFailure.classify("image not decodable: unknown format (12 B)"), .unreadableImage)
        XCTAssertEqual(ScanFailure.classify("boom: models unavailable"), .readerUnavailable)
        XCTAssertEqual(ScanFailure.classify("cancelled"), .other)
        XCTAssertTrue(ScanFailure.noNotesFound(staffCount: 1).explanation.contains("1 staff "))
    }

    func testScanFailureTipsLeadWithPhotoSpecificAdvice() {
        let dark = PhotoQuality(meanLuma: 40, lumaStdDev: 30, pixelWidth: 4032, pixelHeight: 3024)
        let tips = ScanFailure.noStaffFound.tips(quality: dark)
        XCTAssertEqual(tips.first, .dark)
        XCTAssertTrue(tips.contains(.fitPage) && tips.contains(.light))
        XCTAssertEqual(Set(tips.map(\.text)).count, tips.count, "no duplicates")
        let fine = PhotoQuality(meanLuma: 180, lumaStdDev: 50, pixelWidth: 4032, pixelHeight: 3024)
        XCTAssertEqual(ScanFailure.noMusicFound.tips(quality: fine).first, .printed)
        let small = PhotoQuality(meanLuma: 180, lumaStdDev: 10, pixelWidth: 640, pixelHeight: 480)
        XCTAssertEqual(Array(ScanFailure.noNotesFound(staffCount: nil).tips(quality: small).prefix(2)), [.washedOut, .small])
        XCTAssertTrue(ScanFailure.readerUnavailable.tips(quality: dark).isEmpty, "not the photo's fault")
    }

    func testPhotoQualityMeasuresThumbnail() throws {
        let r = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 100), format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
        let black = r.image { ctx in UIColor.black.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 100)) }
        let q = try XCTUnwrap(PhotoQuality.measure(black))
        XCTAssertTrue(q.isDark)
        XCTAssertTrue(q.isSmall)
        XCTAssertEqual(q.pixelWidth, 200)
    }

    static func luminance(_ c: UIColor) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        func lin(_ v: CGFloat) -> Double { let v = Double(v); return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    static func contrast(_ a: Double, _ b: Double) -> Double { (max(a, b) + 0.05) / (min(a, b) + 0.05) }
}
