import SF2Player
import XCTest
@testable import OMRSheetCam

/// App-side SF2 checks: bundled sweden.midi + GeneralUser GS, offline render, real-time player smoke.
final class SF2PlayerAppTests: XCTestCase {
    func testSwedenSampleIsBundledAndParses() throws {
        let midi = try SampleMIDI.sweden()
        let song = try SMFSong(data: midi)
        XCTAssertEqual(song.tracks.count, 2)
        XCTAssertEqual(song.tracks[1].notes.count, 195)
    }

    @MainActor
    func testBundledSoundFontRendersSweden() async throws {
        guard BundledSoundFont.url() != nil else { throw XCTSkip("GeneralUser-GS.sf2 not bundled") }
        let t0 = Date()
        let sf = try await BundledSoundFont.load()
        let parseMs = Int(Date().timeIntervalSince(t0) * 1000)
        XCTAssertEqual(sf.info["INAM"], "GeneralUser GS 2.0.2")
        var plan = try SF2SequenceBuilder.plan(song: SMFSong(data: SampleMIDI.sweden()), soundFont: sf, sampleRate: 44100)
        plan.lengthFrames = 44100 * 3
        let t1 = Date()
        let out = SF2OfflineRenderer.render(plan)
        let renderMs = Int(Date().timeIntervalSince(t1) * 1000)
        let peak = out.left.reduce(Float(0)) { max($0, abs($1)) }
        print("[sf2] parse \(parseMs) ms, 3 s offline render \(renderMs) ms, peak \(peak)")
        XCTAssertGreaterThan(peak, 0.01)
    }

    /// Real-time smoke: engine start is environment-dependent on CI simulators, so audio I/O
    /// failures skip; position must advance when it does run.
    @MainActor
    func testRealtimePlayerAdvancesPosition() async throws {
        guard BundledSoundFont.url() != nil else { throw XCTSkip("GeneralUser-GS.sf2 not bundled") }
        let player = SF2MIDIPlayer()
        try player.load(soundFont: try await BundledSoundFont.load())
        try player.load(midi: try SampleMIDI.sweden())
        XCTAssertEqual(player.duration, 83.478272, accuracy: 1e-6)
        player.tempoScale = 2
        player.play()
        guard player.isPlaying else { throw XCTSkip("audio engine did not start on this simulator") }
        try await Task.sleep(nanoseconds: 1_500_000_000)
        player.refreshPosition()
        print("[sf2] realtime position after 1.5 s at 2x: \(player.position.seconds) s, tick \(player.position.tick)")
        XCTAssertGreaterThan(player.position.seconds, 0.5)
        player.seek(to: 60)
        XCTAssertEqual(player.position.seconds, 60, accuracy: 1e-9)
        player.stop()
        XCTAssertFalse(player.isPlaying)
    }
}
