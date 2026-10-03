import SF2Player
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

    // MARK: - Share MIDI + transpose

    func testMIDIExportFileNamesAndBytes() throws {
        XCTAssertEqual(MIDIExport.fileName(for: "Ode to Joy (sample)"), "Ode to Joy (sample).mid")
        XCTAssertEqual(MIDIExport.fileName(for: "a/b:c"), "a-b-c.mid")
        XCTAssertEqual(MIDIExport.fileName(for: "   "), "Music.mid")
        let midi = try SampleMIDI.cMajorScale()
        let url = try MIDIExport(title: "Scale", source: .data(midi)).writeTemporaryFile()
        XCTAssertEqual(url.lastPathComponent, "Scale.mid")
        XCTAssertEqual(try Data(contentsOf: url), midi)
    }

    @MainActor
    func testLibraryEntriesExportTheirMIDI() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("b16-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PlaylistStore(directory: dir, log: DiagnosticsLog(directory: nil, mirrorToOSLog: false))
        let midi = try SampleMIDI.cMajorScale()
        let scan = try store.addScan(midi: midi, title: "My scan")
        XCTAssertEqual(try store.export(for: scan)?.midiData(), midi)
        let sample = try XCTUnwrap(store.entry(id: "sample:\(SampleMIDI.odeToJoyKey)"))
        XCTAssertEqual(try store.export(for: sample)?.midiData(), try SampleMIDI.odeToJoy())
    }

    @MainActor
    func testTransposeLabels() {
        XCTAssertEqual(PlaybackController.keyLabel(0), "Key 0")
        XCTAssertEqual(PlaybackController.keyLabel(3), "Key +3")
        XCTAssertEqual(PlaybackController.keyLabel(-12), "Key -12")
        XCTAssertEqual(PlaybackController.transposeName(1), "+1 semitone")
        XCTAssertEqual(PlaybackController.transposeName(-2), "-2 semitones")
        XCTAssertEqual(PlaybackController.transposeChoices.first, -12)
        XCTAssertEqual(PlaybackController.transposeChoices.last, 12)
    }

    // MARK: - Note highlighting

    static func sampleLayout() -> ScanLayout {
        let notes = (0 ..< 4).map { i in
            RecognizedNote(noteIndex: i, symbolIndex: i + 2, staffIndex: 0, midiNote: 60 + i, onsetTicks: i * 480, durationTicks: 480,
                           rect: i == 3 ? nil : CGRect(x: 100 + i * 50, y: 200, width: 12, height: 12))
        }
        return ScanLayout(imageWidth: 800, imageHeight: 1100, captureName: "20261003-120000-000.jpg", staffCount: 1,
                          layoutSource: "attention", notes: notes)
    }

    func testScanLayoutRoundTripAndLookups() throws {
        let l = Self.sampleLayout()
        XCTAssertEqual(try ScanLayout.decode(l.encoded()), l)
        XCTAssertEqual(ScanLayout.sidecarName(forMIDI: "20261003-120000-000.mid"), "20261003-120000-000.layout.json")
        XCTAssertEqual(l.boxedNotes.count, 3)
        XCTAssertEqual(l.notePositions.map(\.startTick), [0, 480, 960, 1440])
        XCTAssertEqual(l.notePositions.map(\.endTick), [480, 960, 1440, 1920])
        XCTAssertEqual(l.note(near: CGPoint(x: 155, y: 205), maxDistance: 20)?.noteIndex, 1)
        XCTAssertEqual(l.note(near: CGPoint(x: 170, y: 206), maxDistance: 20)?.noteIndex, 1) // 8 px right of the box
        XCTAssertNil(l.note(near: CGPoint(x: 600, y: 900), maxDistance: 20))
        XCTAssertEqual(l.scrollTarget(for: [2, 3])?.noteIndex, 2)
        XCTAssertNil(l.scrollTarget(for: [3]), "box-less notes can't be scrolled to")
    }

    func testScanLayoutNeedsBoxes() {
        let boxless = RecognitionDetails(midi: Data(), notes: [RecognizedNote(noteIndex: 0, symbolIndex: 0, staffIndex: 0, midiNote: 60,
                                                                               onsetTicks: 0, durationTicks: 480)],
                                         staffCount: 1, warnings: [], layoutSource: "midi-fallback", ms: 1)
        XCTAssertNil(ScanLayout(boxless, imageWidth: 100, imageHeight: 100, captureName: nil))
        var boxed = boxless
        boxed.notes = Self.sampleLayout().notes
        XCTAssertEqual(ScanLayout(boxed, imageWidth: 800, imageHeight: 1100, captureName: "x.jpg")?.notes.count, 4)
    }

    @MainActor
    func testScanLayoutSidecarIsSavedLoadedAndDeleted() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("b16-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PlaylistStore(directory: dir, log: DiagnosticsLog(directory: nil, mirrorToOSLog: false))
        let midi = try SampleMIDI.cMajorScale()
        let plain = try store.addScan(midi: midi, title: "No layout")
        XCTAssertNil(store.layout(for: plain))
        let scan = try store.addScan(midi: midi, title: "With layout", layout: Self.sampleLayout())
        let sidecar = dir.appendingPathComponent(ScanLayout.sidecarName(forMIDI: try XCTUnwrap(scan.fileName)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sidecar.path))
        XCTAssertEqual(store.layout(for: scan), Self.sampleLayout())
        // Reloaded store (app relaunch) still finds it; the index ignores sidecars.
        let reloaded = PlaylistStore(directory: dir, log: DiagnosticsLog(directory: nil, mirrorToOSLog: false))
        XCTAssertEqual(reloaded.entries.filter { $0.source == .scan }.count, 2)
        XCTAssertEqual(reloaded.layout(for: try XCTUnwrap(reloaded.entry(id: scan.id))), Self.sampleLayout())
        try store.delete(scan)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sidecar.path))
        let sample = try XCTUnwrap(store.entry(id: "sample:\(SampleMIDI.odeToJoyKey)"))
        XCTAssertNil(store.layout(for: sample))
    }

    func testActiveNoteIDsAreHalfOpen() {
        let p = Self.sampleLayout().notePositions
        XCTAssertEqual(SF2MIDIPlayer.activeIDs(p, at: 0), [0])
        XCTAssertEqual(SF2MIDIPlayer.activeIDs(p, at: 479.9), [0])
        XCTAssertEqual(SF2MIDIPlayer.activeIDs(p, at: 480), [1])
        XCTAssertEqual(SF2MIDIPlayer.activeIDs(p, at: 5000), [])
    }

    @MainActor
    func testAudibleTickLagsWhilePlayingOnly() throws {
        let player = SF2MIDIPlayer()
        player.outputLatencyOverride = 0.25
        XCTAssertEqual(player.outputLatency, 0.25)
        XCTAssertEqual(player.audibleTick, 0) // not playing: no lag applied
    }

    // MARK: - A–B loop and hands

    func testHandNamesAndLabels() {
        let scan = [SF2TrackInfo(index: 1, name: "Track 2", noteCount: 10), SF2TrackInfo(index: 2, name: "Track 3", noteCount: 6)]
        XCTAssertEqual(PlaybackController.handNames(scan), [1: "Right hand", 2: "Left hand"])
        XCTAssertEqual(PlaybackController.handsLabel(scan, muted: []), "Both hands")
        XCTAssertEqual(PlaybackController.handsLabel(scan, muted: [2]), "Right hand only")
        XCTAssertEqual(PlaybackController.handsLabel(scan, muted: [1]), "Left hand only")
        XCTAssertEqual(PlaybackController.handsLabel(scan, muted: [1, 2]), "All muted")
        let ode = [SF2TrackInfo(index: 1, name: "Right hand", noteCount: 59), SF2TrackInfo(index: 2, name: "Left hand", noteCount: 22)]
        XCTAssertEqual(PlaybackController.handNames(ode), [1: "Right hand", 2: "Left hand"])
        let three = (1 ... 3).map { SF2TrackInfo(index: $0, name: "Track \($0 + 1)", noteCount: 1) }
        XCTAssertEqual(PlaybackController.handNames(three)[3], "Staff 3")
        XCTAssertEqual(PlaybackController.handsLabel(three, muted: [3]), "2 of 3 parts")
    }

    @MainActor
    func testPlayerLoopAndMuteState() async throws {
        guard BundledSoundFont.url() != nil else { throw XCTSkip("GeneralUser-GS.sf2 not bundled") }
        let player = SF2MIDIPlayer()
        try player.load(soundFont: try await BundledSoundFont.load())
        try player.load(midi: try SampleMIDI.odeToJoy())
        XCTAssertEqual(player.noteTracks.map(\.name), ["Right hand", "Left hand"])
        player.solo(player.noteTracks[1].index)
        XCTAssertEqual(player.mutedTracks, [player.noteTracks[0].index])
        player.solo(nil)
        XCTAssertEqual(player.mutedTracks, [])
        player.setLoop(start: 12, end: 4) // reversed: ordered
        XCTAssertEqual(player.loop, SF2LoopRange(start: 4, end: 12))
        XCTAssertEqual(player.position.seconds, 4, accuracy: 1e-9, "seeks into the loop")
        player.setLoop(start: 5, end: 5.01) // too short: cleared
        XCTAssertNil(player.loop)
        player.setLoop(start: 1, end: 2)
        player.setMuted(player.noteTracks[0].index, true)
        try player.load(midi: try SampleMIDI.odeToJoy()) // per song
        XCTAssertNil(player.loop)
        XCTAssertEqual(player.mutedTracks, [])
    }

    // MARK: - Color preprocessing input

    func testColorPhotosDecodeAsRGBXAndGrayScansStayGray() throws {
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.scale = 1
        fmt.opaque = true
        let img = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30), format: fmt).image { ctx in
            UIColor(red: 1, green: 0.95, blue: 0.85, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
            UIColor.black.setFill()
            ctx.fill(CGRect(x: 10, y: 10, width: 5, height: 5))
        }
        let png = try XCTUnwrap(img.pngData())
        guard case let .color(c) = try RGBXImage.decodePage(imageData: png) else { return XCTFail("color photo decoded as gray") }
        XCTAssertEqual([c.width, c.height], [40, 30])
        XCTAssertEqual(c.pixels.count, 40 * 30 * 4)
        let paper = c[x: 2, y: 2], ink = c[x: 12, y: 12]
        XCTAssertGreaterThan(paper.0, paper.2, "warm paper keeps R > B")
        let inkSum: Int = Int(ink.0) + Int(ink.1) + Int(ink.2)
        XCTAssertLessThan(inkSum, 30)
        XCTAssertEqual(c.gray8().count, 40 * 30)

        let gray = try Data(contentsOf: Gate1StaffTokenMatchTests.repoRoot.appendingPathComponent("fixtures/mono.c_major_scale/input.png"))
        guard case let .gray(g) = try RGBXImage.decodePage(imageData: gray) else { return XCTFail("gray fixture decoded as color") }
        XCTAssertEqual(g, try Gray8Image.decode(imageData: gray), "gray scans keep the byte-exact gray path")
    }

    static func luminance(_ c: UIColor) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        func lin(_ v: CGFloat) -> Double { let v = Double(v); return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    static func contrast(_ a: Double, _ b: Double) -> Double { (max(a, b) + 0.05) / (min(a, b) + 0.05) }
}
