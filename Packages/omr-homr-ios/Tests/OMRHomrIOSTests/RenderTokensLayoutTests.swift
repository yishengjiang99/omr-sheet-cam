import XCTest
import CoreGraphics
@testable import OMRHomrIOS

/// Layer C (soft layout): `OMRHomrIOS.renderTokens` builds MIDI + `noteLayout` from ONE shared
/// note-event list. For every repo-root fixture with complete `expected.tokens.json` +
/// `expected.notes.csv`: layout count == sounding notes, entries match the MIDI notes 1:1.
///
/// Linux mirror (runs without Swift): `tools/oracle/check_note_layout.py`.
final class RenderTokensLayoutTests: XCTestCase {

    typealias CanonicalNote = WriterOnlyFixtureTests.CanonicalNote

    func testEveryCompleteFixtureLayoutMatchesMIDINotes() throws {
        let root = try WriterOnlyFixtureTests.fixturesRoot()
        let dirs = try FileManager.default
            .contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var checked: [String] = []
        for dir in dirs {
            let id = dir.lastPathComponent
            let tokensURL = dir.appendingPathComponent("expected.tokens.json")
            let notesURL = dir.appendingPathComponent("expected.notes.csv")
            guard FileManager.default.fileExists(atPath: tokensURL.path),
                  FileManager.default.fileExists(atPath: notesURL.path)
            else { continue }

            let fixture = try WriterOnlyFixtureTests.loadTokenFixture(from: tokensURL)
            // Stubs / awaiting oracle export have no tokens yet — nothing to render.
            guard fixture.status == "complete", !fixture.symbols.isEmpty else { continue }

            let symbols = fixture.symbols.map { EncodedSymbol(oracleFields: $0) }
            let expected = try WriterOnlyFixtureTests.loadNotesCSV(from: notesURL)
            let result = OMRHomrIOS.renderTokens(symbols)
            let layout = result.noteLayout
            let ordered = SymbolMIDIMapping.orderedNoteEvents(from: symbols)

            // 1. Count == sounding notes (the only Layer C fail condition).
            XCTAssertEqual(layout.count, expected.count, "\(id): highlight count != sounding notes")
            XCTAssertEqual(layout.count, ordered.count, "\(id): layout count != MIDI note count")

            // 2. One-to-one with the shared MIDI note list.
            for (k, pair) in zip(layout, ordered).enumerated() {
                let (entry, sourced) = pair
                XCTAssertEqual(entry.noteIndex, k, "\(id)[\(k)] noteIndex")
                XCTAssertEqual(entry.symbolIndex, sourced.symbolIndex, "\(id)[\(k)] symbolIndex")
                XCTAssertEqual(entry.onsetTicks, sourced.event.onsetTicks, "\(id)[\(k)] tick")
                XCTAssertEqual(entry.midiNote, Int(sourced.event.midiNote), "\(id)[\(k)] pitch")
                XCTAssertEqual(entry.durationTicks, sourced.event.durationTicks, "\(id)[\(k)] duration")
                XCTAssertEqual(entry.staffIndex, sourced.event.staff, "\(id)[\(k)] staff")
                XCTAssertTrue(entry.pageRect.isNull, "\(id)[\(k)] must not fabricate a box")
                XCTAssertFalse(entry.hasBox, "\(id)[\(k)] hasBox")
                XCTAssertTrue(
                    symbols[entry.symbolIndex].rhythm.hasPrefix("note_"),
                    "\(id)[\(k)] symbolIndex should point at a note_* symbol"
                )
            }

            // 3. Same notes as expected.notes.csv (multiset).
            let actual = layout.map {
                CanonicalNote(
                    tick: $0.onsetTicks,
                    pitch: $0.midiNote ?? -1,
                    duration: $0.durationTicks,
                    staff: $0.staffIndex
                )
            }
            XCTAssertEqual(actual.sorted(), expected.sorted(), "\(id): layout notes != expected.notes.csv")

            // 4. Documented ordering: (tick, staff, pitch) ascending.
            let keys = layout.map { [$0.onsetTicks, $0.staffIndex, $0.midiNote ?? -1] }
            for k in keys.indices.dropFirst() {
                XCTAssertTrue(
                    keys[k - 1].lexicographicallyPrecedes(keys[k]) || keys[k - 1] == keys[k],
                    "\(id): order broken at \(k): \(keys[k - 1]) > \(keys[k])"
                )
            }

            // 5. The SMF emits note-ons in exactly noteLayout order.
            let ons = Self.noteOns(in: result.midi)
            XCTAssertEqual(ons.map(\.tick), layout.map(\.onsetTicks), "\(id): SMF note-on ticks")
            XCTAssertEqual(ons.map(\.pitch), layout.compactMap(\.midiNote), "\(id): SMF note-on pitches")
            XCTAssertEqual(SMFHeaderInspector.readHeader(from: result.midi)?.division, 480, id)

            // 6. No attention boxes yet → midi-fallback.
            XCTAssertEqual(result.layoutSource, .midiFallback, id)
            XCTAssertEqual(result.layoutSource.rawValue, "midi-fallback", id)
            XCTAssertEqual(result.staffCount, Set(expected.map(\.staff)).count, "\(id) staffCount")

            checked.append(id)
        }

        // Guard against silently checking nothing (7 writer-complete fixtures today).
        XCTAssertTrue(
            Set(WriterOnlyFixtureTests.writerReadyIDs).isSubset(of: Set(checked)),
            "checked=\(checked)"
        )
    }

    func testRestsProduceNoEntriesAndChordsShareOnset() throws {
        let symbols: [EncodedSymbol] = [
            EncodedSymbol(rhythm: "clef_G2", position: "upper"),
            EncodedSymbol(rhythm: "note_4", pitch: "C4", lift: "_", position: "upper"),
            EncodedSymbol(rhythm: "rest_4", position: "upper"),
            EncodedSymbol(rhythm: "note_4", pitch: "G4", lift: "_", position: "upper"),
            EncodedSymbol(rhythm: "chord"),
            EncodedSymbol(rhythm: "note_4", pitch: "E4", lift: "_", position: "upper"),
        ]
        let result = OMRHomrIOS.renderTokens(symbols)
        XCTAssertEqual(result.noteLayout.map(\.midiNote), [60, 64, 67])
        XCTAssertEqual(result.noteLayout.map(\.onsetTicks), [0, 960, 960])
        XCTAssertEqual(result.noteLayout.map(\.symbolIndex), [1, 5, 3])
        XCTAssertEqual(result.noteLayout.map(\.noteIndex), [0, 1, 2])
    }

    func testGrandStaffOrdersTopStaffFirstAtEachTick() throws {
        let root = try WriterOnlyFixtureTests.fixturesRoot()
        let fixture = try WriterOnlyFixtureTests.loadTokenFixture(
            from: root.appendingPathComponent("piano.grand/expected.tokens.json")
        )
        let result = OMRHomrIOS.renderTokens(fixture.symbols.map { EncodedSymbol(oracleFields: $0) })
        XCTAssertEqual(result.staffCount, 2)
        XCTAssertEqual(result.noteLayout.count, 32)
        XCTAssertEqual(result.noteLayout.prefix(2).map(\.staffIndex), [0, 1])
        XCTAssertEqual(result.noteLayout.prefix(2).map(\.midiNote), [60, 48])
    }

    func testStaffIndexOffsetShiftsStaves() {
        let symbols = [EncodedSymbol(rhythm: "note_4", pitch: "C4", lift: "_", position: "upper")]
        let result = OMRHomrIOS.renderTokens(symbols, staffIndexOffset: 3)
        XCTAssertEqual(result.noteLayout.map(\.staffIndex), [3])
    }

    func testBoxProviderSeam() {
        struct Boxes: NoteBoxProvider {
            var only: Set<Int>?
            func pageRect(forSymbolAt symbolIndex: Int, symbol: EncodedSymbol) -> CGRect? {
                if let only, !only.contains(symbolIndex) { return nil }
                return CGRect(x: symbolIndex * 10, y: 0, width: 8, height: 20)
            }
        }
        let symbols = [
            EncodedSymbol(rhythm: "note_4", pitch: "C4", lift: "_", position: "upper"),
            EncodedSymbol(rhythm: "note_4", pitch: "D4", lift: "_", position: "upper"),
        ]
        let full = OMRHomrIOS.renderTokens(symbols, boxProvider: Boxes(only: nil))
        XCTAssertEqual(full.layoutSource, .attention)
        XCTAssertTrue(full.noteLayout.allSatisfy(\.hasBox))

        let partial = OMRHomrIOS.renderTokens(symbols, boxProvider: Boxes(only: [0]))
        XCTAssertEqual(partial.layoutSource, .midiFallback)
        XCTAssertEqual(partial.noteLayout.map(\.hasBox), [true, false])
    }

    // MARK: - Minimal SMF note-on reader (note tracks only; writer never uses running status)

    struct NoteOn: Equatable {
        var tick: Int
        var pitch: Int
    }

    static func noteOns(in smf: Data) -> [NoteOn] {
        let b = [UInt8](smf)
        var out: [NoteOn] = []
        var i = 14
        var track = 0
        while i + 8 <= b.count {
            let len = Int(b[i + 4]) << 24 | Int(b[i + 5]) << 16 | Int(b[i + 6]) << 8 | Int(b[i + 7])
            let start = i + 8
            let end = min(b.count, start + len)
            if track >= 1 {
                var j = start
                var tick = 0
                while j < end {
                    var delta = 0
                    while j < end {
                        let byte = b[j]
                        j += 1
                        delta = (delta << 7) | Int(byte & 0x7F)
                        if byte & 0x80 == 0 { break }
                    }
                    tick += delta
                    guard j < end else { break }
                    let status = b[j]
                    if status == 0xFF {
                        guard j + 2 < end else { break }
                        j += 3 + Int(b[j + 2])
                    } else {
                        guard j + 2 < end else { break }
                        if status & 0xF0 == 0x90, b[j + 2] > 0 {
                            out.append(NoteOn(tick: tick, pitch: Int(b[j + 1])))
                        }
                        j += 3
                    }
                }
            }
            track += 1
            i = start + len
        }
        return out
    }
}
