import SF2Player
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

    /// Nothing the mapper returns may contain implementation text.
    private func assertPlain(_ msg: String, file: StaticString = #filePath, line: UInt = #line) {
        for raw in ["Error Domain", "NSCocoaErrorDomain", "UserInfo", "notFound", "invalidMIDI", "SF2", "PlayerError", "StoreError", "Optional(", "(\"", "/"] {
            XCTAssertFalse(msg.contains(raw), "leaked \(raw): \(msg)", file: file, line: line)
        }
        XCTAssertLessThan(msg.count, 140, "keep it short: \(msg)", file: file, line: line)
    }

    func testStoreErrorsMapToPlainLanguage() {
        let m1 = UserFacingError.message(for: PlaylistStore.StoreError.notFound("2026-10-17.mid"), action: .play)
        XCTAssertEqual(m1, "Can't play this. This scan is no longer in your Library.")
        let m2 = UserFacingError.message(for: PlaylistStore.StoreError.notDeletable("Ode to Joy (sample)"), action: .delete)
        XCTAssertEqual(m2, "Couldn't delete this scan. Bundled samples can't be changed.")
        let m3 = UserFacingError.message(for: PlaylistStore.StoreError.invalidMIDI("SMFError.badHeader"), action: .saveToLibrary)
        XCTAssertEqual(m3, "Couldn't save to your Library. The music file couldn't be read.")
        for m in [m1, m2, m3] { assertPlain(m) }
    }

    func testPlayerAndSoundFontErrors() {
        XCTAssertEqual(UserFacingError.message(for: BundledSoundFont.LoadError.missing, action: .play),
                       "Can't play this. The piano sounds are missing. Reinstalling the app should fix this.")
        let audio = UserFacingError.message(for: SF2MIDIPlayer.PlayerError.audio("AVAudioSession: -50"), action: .play)
        XCTAssertFalse(audio.contains("-50"))
        assertPlain(audio)
        assertPlain(UserFacingError.message(for: SF2MIDIPlayer.PlayerError.noSequence, action: .play))
    }

    func testFileSystemErrors() {
        let missing = CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: "/var/mobile/x.mid"])
        XCTAssertEqual(UserFacingError.message(for: missing, action: .play), "Can't play this. The file is missing. It may have been deleted.")
        let full = CocoaError(.fileWriteOutOfSpace)
        XCTAssertEqual(UserFacingError.message(for: full, action: .saveCapture), "Couldn't save the photo. Your device is out of storage space.")
        assertPlain(UserFacingError.message(for: missing, action: .play))
    }

    func testUnknownErrorsNeverLeakRawText() {
        struct Weird: Error, CustomStringConvertible { var description: String { "Weird(secret: /private/var/x, code: 42)" } }
        for action in [UserFacingError.Action.play, .saveCapture, .saveToLibrary, .delete, .rename, .sample, .capture] {
            let m = UserFacingError.message(for: Weird(), action: action)
            XCTAssertFalse(m.contains("secret") || m.contains("42"), m)
            assertPlain(m)
            XCTAssertTrue(m.hasPrefix(action.lead), m)
        }
        XCTAssertEqual(UserFacingError.message(for: Weird(), action: .rename), "Couldn't rename this scan. Please try again.")
    }

    func testSampleAndCaptureErrors() {
        XCTAssertEqual(UserFacingError.message(for: SampleMIDI.SampleError.missing("ode-to-joy.mid"), action: .sample),
                       "The sample isn't available. The sample file is missing from this build.")
        assertPlain(UserFacingError.message(for: CaptureStore.SaveError.encodeFailed, action: .saveCapture))
    }
}
