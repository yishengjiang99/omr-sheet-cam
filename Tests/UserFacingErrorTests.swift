import XCTest
@testable import OMRSheetCam

/// F10.3: users see short plain-language errors; raw Swift/NSError text stays in the diagnostics log.
@MainActor
final class UserFacingErrorTests: XCTestCase {
    private var dir: URL = FileManager.default.temporaryDirectory
        .appendingPathComponent("user-facing-error-tests-\(UUID().uuidString)", isDirectory: true)
    private let log = DiagnosticsLog(directory: nil, mirrorToOSLog: false)

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    /// Player status when the scan's .mid vanished from disk: used to read
    /// "Can't play this: Error Domain=NSCocoaErrorDomain Code=260 ... /var/mobile/.../x.mid".
    func testPlayerStatusForMissingMIDIFileIsPlainLanguage() async throws {
        guard BundledSoundFont.url() != nil else { throw XCTSkip("GeneralUser-GS.sf2 not bundled") }
        let store = PlaylistStore(directory: dir, samples: [], log: log)
        let e = try store.addScan(midi: try SampleMIDI.cMajorScale(), title: "Vanishing scan")
        try FileManager.default.removeItem(at: dir.appendingPathComponent(try XCTUnwrap(e.fileName)))
        let c = PlaybackController(store: store, settings: .shared)
        var route = PlayerRoute(entry: e)
        route.autoplay = false
        c.open(route, reason: "test")
        for _ in 0 ..< 120 where !c.status.hasPrefix("Can't play") { try await Task.sleep(nanoseconds: 250_000_000) }

        let status = c.status
        XCTAssertTrue(status.hasPrefix("Can't play"), "unexpected status: \(status)")
        for raw in ["Error Domain", "NSCocoaErrorDomain", "NSUnderlyingError", ".mid", "notFound", "UserInfo", "/"] {
            XCTAssertFalse(status.contains(raw), "raw error text leaked to the user (\(raw)): \(status)")
        }
        XCTAssertFalse(c.ready)
    }
}
