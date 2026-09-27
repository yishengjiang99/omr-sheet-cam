import XCTest
@testable import OMRSheetCam

/// Auto-advance only happens in playlist mode: a just-scanned sheet plays once
/// and stops; playback started from the Library keeps going at track end.
@MainActor
final class PlaybackAutoAdvanceTests: XCTestCase {
    private var dir: URL = FileManager.default.temporaryDirectory
        .appendingPathComponent("auto-advance-tests-\(UUID().uuidString)", isDirectory: true)
    private let log = DiagnosticsLog(directory: nil, mirrorToOSLog: false)

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func makeController() throws -> (PlaybackController, PlaylistEntry, PlaylistEntry) {
        let store = PlaylistStore(directory: dir, samples: [], log: log)
        let midi = try SampleMIDI.cMajorScale()
        let e1 = try store.addScan(midi: midi, title: "scan one")
        let e2 = try store.addScan(midi: midi, title: "scan two")
        let controller = PlaybackController(store: store, settings: .shared)
        return (controller, e1, e2)
    }

    func testScanPlaybackDoesNotAutoAdvance() throws {
        let (c, e1, _) = try makeController()
        var route = PlayerRoute(entry: e1) // what ResultScreen.playScan opens
        XCTAssertFalse(route.advanceOnFinish)
        c.open(route, reason: "scan")
        XCTAssertNil(c.autoNextRoute(), "a just-scanned sheet must stop at the end")
    }

    func testLibraryPlaybackAutoAdvances() throws {
        let (c, e1, e2) = try makeController()
        var route = PlayerRoute(entry: e1) // what the Library list opens
        route.advanceOnFinish = true
        c.open(route, reason: "library")
        let next = try XCTUnwrap(c.autoNextRoute())
        XCTAssertEqual(next.item, .playlist(e2.id))
        XCTAssertTrue(next.advanceOnFinish, "auto-advance stays engaged down the list")
    }

    func testManualNextEngagesPlaylistMode() throws {
        let (c, e1, e2) = try makeController()
        c.open(PlayerRoute(entry: e1), reason: "scan") // no flag
        XCTAssertNil(c.autoNextRoute())
        c.next() // user taps next: now browsing the list
        XCTAssertEqual(c.current?.item, .playlist(e2.id))
        XCTAssertTrue(c.current?.advanceOnFinish == true)
    }

    func testNoNextItemStopsRegardlessOfMode() throws {
        let (c, _, e2) = try makeController()
        var route = PlayerRoute(entry: e2) // last in the list
        route.advanceOnFinish = true
        c.open(route, reason: "library")
        XCTAssertNil(c.autoNextRoute(), "nothing after the last item")
    }
}
