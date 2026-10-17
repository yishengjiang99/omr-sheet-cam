import MediaPlayer
import XCTest
@testable import OMRSheetCam

/// F10.10: a music player must keep playing with the screen locked (UIBackgroundModes = audio) and
/// expose lock-screen controls (MPNowPlayingInfoCenter + MPRemoteCommandCenter).
///
/// What is and isn't covered: the Info.plist assertion reads the *built host app's* plist at run
/// time (hosted tests run inside the app), so it proves the capability is in the shipped bundle.
/// That audio really survives a screen lock, and what the lock screen looks like, can only be
/// verified on a device; those are the manual checks in the PR.
@MainActor
final class BackgroundAudioTests: XCTestCase {
    private var dir: URL = FileManager.default.temporaryDirectory
        .appendingPathComponent("bg-audio-tests-\(UUID().uuidString)", isDirectory: true)
    private let log = DiagnosticsLog(directory: nil, mirrorToOSLog: false)

    override func tearDown() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    func testInfoPlistDeclaresAudioBackgroundMode() throws {
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
        XCTAssertEqual(modes, ["audio"], "UIBackgroundModes must be exactly [audio] (App Review: only declare what is used)")
    }

    func testRemoteCommandsAreEnabledForTransport() throws {
        let store = PlaylistStore(directory: dir, samples: [], log: log)
        _ = PlaybackController(store: store, settings: .shared)
        let cc = MPRemoteCommandCenter.shared()
        XCTAssertTrue(cc.playCommand.isEnabled, "lock-screen play")
        XCTAssertTrue(cc.pauseCommand.isEnabled, "lock-screen pause")
        XCTAssertTrue(cc.togglePlayPauseCommand.isEnabled, "headset / lock-screen toggle")
        XCTAssertTrue(cc.changePlaybackPositionCommand.isEnabled, "lock-screen scrubber")
    }

    func testNowPlayingInfoIsPopulatedOnceLoaded() async throws {
        guard BundledSoundFont.url() != nil else { throw XCTSkip("GeneralUser-GS.sf2 not bundled") }
        let store = PlaylistStore(directory: dir, samples: [], log: log)
        let e = try store.addScan(midi: try SampleMIDI.cMajorScale(), title: "Lock screen scan")
        let c = PlaybackController(store: store, settings: .shared)
        var route = PlayerRoute(entry: e)
        route.autoplay = false
        c.open(route, reason: "test")
        for _ in 0 ..< 120 where !c.ready { try await Task.sleep(nanoseconds: 250_000_000) }
        XCTAssertTrue(c.ready, "song failed to load: \(c.status)")

        let info = try XCTUnwrap(MPNowPlayingInfoCenter.default().nowPlayingInfo, "Now Playing info must be set after load")
        XCTAssertEqual(info[MPMediaItemPropertyTitle] as? String, "Lock screen scan")
        XCTAssertEqual(info[MPMediaItemPropertyPlaybackDuration] as? Double ?? 0, c.player.duration, accuracy: 0.01)
        XCTAssertGreaterThan(c.player.duration, 0)
        XCTAssertEqual(info[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 0, "paused, not playing")
    }
}
