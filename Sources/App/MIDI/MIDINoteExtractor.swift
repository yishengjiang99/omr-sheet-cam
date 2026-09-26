import Foundation
import OMRHomrIOS

/// App-side name for one sounding note recovered from SMF bytes.
///
/// Same type as the package's headless reader (`OMRHomrIOS.SMFNote`): `track` is the `MTrk`
/// chunk index (format 1: 0 = conductor) and `staff` is `track - 1` (zero-based, top → bottom,
/// matching the `expected.notes.csv` `staff` column).
typealias MIDINote = SMFNote

/// Thin app-side wrapper over `OMRHomrIOS.SMFNoteReader` for playback + highlight smoke
/// ("midi-fallback" note source). All SMF parsing (running status, velocity-0 note-off,
/// meta / sysex skipping, unterminated notes) lives in the package and is unit-tested there
/// (`SMFNoteReaderFixtureTests`) — do not re-implement byte parsing here.
enum MIDINoteExtractor {

    typealias Header = SMFNoteReader.Header
    typealias ExtractError = SMFNoteReader.ReadError

    /// Sounding notes sorted by `(tick, track, pitch)`.
    static func notes(from data: Data) throws -> [MIDINote] {
        try SMFNoteReader.notes(from: data)
    }

    /// Count of note-on events with velocity > 0 (the "sounding note" count).
    static func soundingNoteCount(in data: Data) throws -> Int {
        try notes(from: data).count
    }

    static func extract(from data: Data) throws -> (header: Header, notes: [MIDINote]) {
        let contents = try SMFNoteReader.read(from: data)
        return (contents.header, contents.notes)
    }
}
