import XCTest
@testable import OMRHomrIOS

final class SMFWriterTests: XCTestCase {
    func testEmptyFileIsFormat1_480TPQ_TwoTracks() {
        let data = SMFWriter().writeEmpty()
        let header = SMFHeaderInspector.readHeader(from: data)
        XCTAssertNotNil(header)
        XCTAssertEqual(header?.format, 1)
        XCTAssertEqual(header?.trackCount, 2)
        XCTAssertEqual(header?.division, 480)
        XCTAssertEqual(SMFHeaderInspector.trackChunkCount(in: data), 2)
        XCTAssertEqual(String(data: data[0..<4], encoding: .ascii), "MThd")
        XCTAssertTrue(
            SMFHeaderInspector.containsTimeSignatureMeta(in: data),
            "metrical SMF should include FF 58 time signature on conductor track"
        )
    }

    func testSingleNoteWritesNoteTrack() {
        let notes = [
            SMFWriter.NoteEvent(midiNote: 60, onsetTicks: 0, durationTicks: 480),
            SMFWriter.NoteEvent(midiNote: 62, onsetTicks: 480, durationTicks: 480),
        ]
        let data = SMFWriter().write(notes: notes)
        let header = SMFHeaderInspector.readHeader(from: data)!
        XCTAssertEqual(header.format, 1)
        XCTAssertEqual(header.division, 480)
        XCTAssertGreaterThan(data.count, 30)
    }

    func testVLQEncoding() {
        XCTAssertEqual(SMFWriter.encodeVLQ(0), [0x00])
        XCTAssertEqual(SMFWriter.encodeVLQ(0x7F), [0x7F])
        XCTAssertEqual(SMFWriter.encodeVLQ(0x80), [0x81, 0x00])
        XCTAssertEqual(SMFWriter.encodeVLQ(480), [0x83, 0x60])
    }

    func testCScaleSymbolMappingUsesTokenizerStringsOnly() {
        // Pitch/rhythm strings from Vocabulary — not invented IDs.
        let symbols: [EncodedSymbol] = [
            EncodedSymbol(rhythm: "clef_G2", pitch: ".", lift: ".", articulation: ".", slur: ".", position: "upper"),
            EncodedSymbol(rhythm: "note_4", pitch: "C4", lift: "_", articulation: "_", slur: "_", position: "upper"),
            EncodedSymbol(rhythm: "note_4", pitch: "D4", lift: "_", articulation: "_", slur: "_", position: "upper"),
            EncodedSymbol(rhythm: "note_4", pitch: "E4", lift: "_", articulation: "_", slur: "_", position: "upper"),
            EncodedSymbol(rhythm: "note_4", pitch: "F4", lift: "_", articulation: "_", slur: "_", position: "upper"),
            EncodedSymbol(rhythm: "note_4", pitch: "G4", lift: "_", articulation: "_", slur: "_", position: "upper"),
            EncodedSymbol(rhythm: "note_4", pitch: "A4", lift: "_", articulation: "_", slur: "_", position: "upper"),
            EncodedSymbol(rhythm: "note_4", pitch: "B4", lift: "_", articulation: "_", slur: "_", position: "upper"),
            EncodedSymbol(rhythm: "note_4", pitch: "C5", lift: "_", articulation: "_", slur: "_", position: "upper"),
        ]
        let events = SymbolMIDIMapping.noteEvents(from: symbols)
        XCTAssertEqual(events.map(\.midiNote), [60, 62, 64, 65, 67, 69, 71, 72])
        XCTAssertEqual(events.map(\.onsetTicks), [0, 480, 960, 1440, 1920, 2400, 2880, 3360])
        XCTAssertEqual(Set(events.map(\.durationTicks)), [480])

        let data = SMFWriter().write(symbols: symbols)
        let header = SMFHeaderInspector.readHeader(from: data)!
        XCTAssertEqual(header.format, 1)
        XCTAssertEqual(header.division, 480)
        XCTAssertTrue(SMFHeaderInspector.containsTimeSignatureMeta(in: data))
    }

    func testKernQuarterAndDotted() {
        XCTAssertEqual(SymbolMIDIMapping.durationTicks(rhythmToken: "note_4"), 480)
        XCTAssertEqual(SymbolMIDIMapping.durationTicks(rhythmToken: "note_8"), 240)
        XCTAssertEqual(SymbolMIDIMapping.durationTicks(rhythmToken: "note_4."), 720)
        XCTAssertEqual(SymbolMIDIMapping.durationTicks(rhythmToken: "rest_4"), 480)
        XCTAssertEqual(SymbolMIDIMapping.midiNote(pitchToken: "C4"), 60)
        XCTAssertEqual(SymbolMIDIMapping.midiNote(pitchToken: "C4", liftToken: "#"), 61)
        XCTAssertNil(SymbolMIDIMapping.midiNote(pitchToken: "."))
    }
}
