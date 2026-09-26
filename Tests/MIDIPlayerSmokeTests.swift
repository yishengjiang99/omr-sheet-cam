import XCTest
import OMRHomrIOS
@testable import OMRSheetCam

/// Optional MIDI smoke: build a tiny valid SMF via public SMFWriter and prepare AVMIDIPlayer.
final class MIDIPlayerSmokeTests: XCTestCase {
    func testSMFWriterEmptyHasValidHeader() {
        let data = SMFWriter().writeEmpty()
        let header = SMFHeaderInspector.readHeader(from: data)
        XCTAssertNotNil(header)
        XCTAssertEqual(header?.format, 1)
        XCTAssertEqual(header?.division, SMFWriter.ticksPerQuarter)
        XCTAssertEqual(SMFHeaderInspector.trackChunkCount(in: data), 2)
    }

    func testSMFWriterSingleNoteAndPreparePlayer() throws {
        let writer = SMFWriter()
        let data = writer.write(notes: [
            SMFWriter.NoteEvent(midiNote: 60, onsetTicks: 0, durationTicks: 480),
        ])
        XCTAssertNotNil(SMFHeaderInspector.readHeader(from: data))

        // prepareOnly validates SMF and constructs AVMIDIPlayer without starting I/O.
        // On simulator/device this should succeed; skip if sound bank unavailable.
        do {
            let player = try SimpleMIDIPlayer.prepareOnly(midiData: data)
            XCTAssertFalse(player.isPlaying)
        } catch {
            throw XCTSkip("AVMIDIPlayer unavailable in this environment: \(error)")
        }
    }

    func testRejectEmptyMIDI() {
        XCTAssertThrowsError(try SimpleMIDIPlayer.prepareOnly(midiData: Data())) { error in
            XCTAssertEqual(error as? SimpleMIDIPlayer.PlayerError, .emptyData)
        }
    }
}
