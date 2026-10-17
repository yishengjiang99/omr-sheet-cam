import XCTest
@testable import OMRSheetCam

/// F11.2: deleting the scan that is loaded/playing must stop playback and clear the mini-player
/// (`PlaybackController.current == nil`), not leave a ghost item whose prev/next are dead.
@MainActor
final class PlaybackDeleteTests: XCTestCase {
    private var dir: URL = FileManager.default.temporaryDirectory
        .appendingPathComponent("playback-delete-tests-\(UUID().uuidString)", isDirectory: true)
    private let log = DiagnosticsLog(directory: nil, mirrorToOSLog: false)

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func makeController() throws -> (PlaybackController, PlaylistStore, PlaylistEntry, PlaylistEntry) {
        let store = PlaylistStore(directory: dir, samples: PlaylistSample.bundled, log: log)
        let midi = try SampleMIDI.cMajorScale()
        let e1 = try store.addScan(midi: midi, title: "scan one", captureName: "f112-one.jpg")
        let e2 = try store.addScan(midi: midi, title: "scan two", captureName: "f112-two.jpg")
        return (PlaybackController(store: store, settings: .shared), store, e1, e2)
    }

    func testDeletingTheLoadedScanClearsCurrentAndStopsPlayback() async throws {
        let (c, store, e1, _) = try makeController()
        var route = PlayerRoute(entry: e1)
        route.autoplay = false
        c.open(route, reason: "test")
        XCTAssertEqual(c.entryID, e1.id)

        try store.delete(e1)

        XCTAssertNil(c.current, "mini-player must disappear when its scan is deleted")
        XCTAssertNil(c.entryID)
        XCTAssertFalse(c.player.isPlaying)
        XCTAssertFalse(c.ready)
        // A late-finishing load of the deleted scan must not resurrect it.
        try await Task.sleep(nanoseconds: 1_500_000_000)
        XCTAssertNil(c.current)
    }

    func testDeletingAnotherScanKeepsPlaybackLoaded() throws {
        let (c, store, e1, e2) = try makeController()
        var route = PlayerRoute(entry: e1)
        route.autoplay = false
        c.open(route, reason: "test")
        try store.delete(e2)
        XCTAssertEqual(c.entryID, e1.id, "unrelated delete must not stop the current item")
    }

    func testPlayingASampleIsUnaffectedByDeletingScans() throws {
        let (c, store, e1, _) = try makeController()
        var route = PlayerRoute.sample(SampleMIDI.odeToJoyKey, title: "Ode", autoplay: false)
        route.autoplay = false
        c.open(route, reason: "test")
        try store.delete(e1)
        XCTAssertEqual(c.entryID, "sample:\(SampleMIDI.odeToJoyKey)")
    }
}
