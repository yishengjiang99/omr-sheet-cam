import XCTest
@testable import OMRHomrIOS

/// Grand-staff timing: each hand keeps its own cursor, so a long note in one hand never delays the other.
final class HandTimingTests: XCTestCase {
    private func s(_ r: String, _ p: String = "_", _ pos: String = "upper") -> EncodedSymbol {
        EncodedSymbol(rhythm: r, pitch: p, lift: "_", articulation: "_", slur: "_", position: pos)
    }

    /// Die Letzte Kompanie bar 1: dotted eighth + 16th in the treble over a half-note bass chord.
    func testUpperHandDoesNotWaitForLowerHandHalfNoteChord() {
        let bar = [s("note_8.", "G4"), s("chord"), s("note_2", "D3", "lower"), s("chord"), s("note_2", "B2", "lower"),
                   s("note_16", "G4"), s("note_8", "G4"), s("note_8", "A4"),
                   s("note_4", "B4"), s("chord"), s("note_2", "F3", "lower")]
        XCTAssertEqual(SymbolMIDIMapping.noteEvents(from: bar).map(\.onsetTicks),
                       [0, 0, 0, 360, 480, 720, 960, 960])
    }

    func testChordTiedRestLastsOnlyItsOwnLength() {
        let bar = [s("note_2", "G4"), s("chord"), s("rest_4", "_", "lower"), s("note_4", "C3", "lower"), s("note_2", "A4")]
        XCTAssertEqual(SymbolMIDIMapping.noteEvents(from: bar).map(\.onsetTicks), [0, 480, 960])
    }

    /// A new system starting with an interleaved upper note keeps that note's time.
    func testRowStartingWithUpperNoteKeepsItsDuration() {
        let rows = [s("note_4", "C4"), s("chord"), s("note_2", "C3", "lower"), s("note_4", "D4"), s("newline"),
                    s("note_4", "E4"), s("chord"), s("note_2", "E3", "lower"), s("note_4", "F4")]
        let e = SymbolMIDIMapping.pageVoiceEvents(from: rows).map(\.event.onsetTicks)
        XCTAssertEqual(e.sorted(), [0, 0, 480, 960, 960, 1440])
    }
}
