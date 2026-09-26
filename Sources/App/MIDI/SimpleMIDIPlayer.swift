import Foundation
import OMRHomrIOS
import AVFoundation

/// Minimal SMF smoke player. Plays `result.midi` (or any Format-1 SMF) via AVMIDIPlayer.
/// Not a production sequencer — Gate-1 linkage / audible smoke only.
@Observable
final class SimpleMIDIPlayer {
    private var player: AVMIDIPlayer?
    private(set) var statusText: String = "idle"

    /// Prepare and start playback of Standard MIDI File bytes.
    func play(midiData: Data) throws {
        stop()
        guard !midiData.isEmpty else {
            statusText = "empty MIDI data"
            throw PlayerError.emptyData
        }
        guard SMFHeaderInspector.readHeader(from: midiData) != nil else {
            statusText = "not a valid SMF header"
            throw PlayerError.invalidSMF
        }

        let player = try AVMIDIPlayer(data: midiData, soundBankURL: nil)
        self.player = player
        player.prepareToPlay()
        player.play()
        statusText = "playing (\(midiData.count) bytes, format check OK)"
    }

    func stop() {
        player?.stop()
        player = nil
        if statusText.hasPrefix("playing") {
            statusText = "stopped"
        }
    }

    /// Unit-test helper: validate SMF and construct player without starting audio I/O.
    static func prepareOnly(midiData: Data) throws -> AVMIDIPlayer {
        guard !midiData.isEmpty else { throw PlayerError.emptyData }
        guard SMFHeaderInspector.readHeader(from: midiData) != nil else {
            throw PlayerError.invalidSMF
        }
        let player = try AVMIDIPlayer(data: midiData, soundBankURL: nil)
        player.prepareToPlay()
        return player
    }

    enum PlayerError: Error, Equatable {
        case emptyData
        case invalidSMF
    }
}
