import XCTest
import OMRHomrIOS
@testable import OMRSheetCam

/// Test-ladder step 6 — **Playback smoke** (Layer C, soft). See `docs/TESTING.md`.
///
/// Driven by the writer-only fixtures at repo-root `fixtures/` (resolved via `#filePath`,
/// no bundle copy). No images, no model inference:
///
///   `expected.tokens.json` → `[EncodedSymbol]` → `SMFWriter.write(symbols:)` → SMF bytes
///
/// Per fixture:
///   (a) SMF bytes load in the project player (`SimpleMIDIPlayer.prepareOnly` → `AVMIDIPlayer`);
///       XCTSkip if AVMIDIPlayer / default sound bank is unavailable in this environment.
///   (b) sounding notes parsed back out of the SMF (`MIDINoteExtractor`, note-on vel > 0)
///       == row count of `expected.notes.csv` (and == `SymbolMIDIMapping.noteEvents` count).
///   (c) Layer C highlight rule: highlight count == sounding note count, and every sounding
///       note has a layout entry OR `layoutSource == .midiFallback`.
///
/// Only public OMRHomrIOS API is used (`SMFWriter`, `SymbolMIDIMapping`, `SMFHeaderInspector`,
/// `EncodedSymbol`, `NoteLayout`, `LayoutSource`).
final class PlaybackSmokeFixtureTests: XCTestCase {

    // MARK: - (a) Project player loads SMF

    func testFixtureSMFLoadsInProjectPlayer() throws {
        let fixtures = try Self.loadPlayableFixtures()
        var unavailable: [String] = []

        for fx in fixtures {
            let smf = SMFWriter().write(symbols: fx.symbols)
            let header = SMFHeaderInspector.readHeader(from: smf)
            XCTAssertEqual(header?.format, 1, "\(fx.id) SMF format")
            XCTAssertEqual(header?.division, SMFWriter.ticksPerQuarter, "\(fx.id) SMF division")

            do {
                let player = try SimpleMIDIPlayer.prepareOnly(midiData: smf)
                XCTAssertFalse(player.isPlaying, "\(fx.id) prepareOnly must not start audio")
                XCTAssertGreaterThan(player.duration, 0, "\(fx.id) player duration should be > 0 for non-empty SMF")
            } catch let error as SimpleMIDIPlayer.PlayerError {
                // Our own validation rejected writer output → real failure, not environment.
                XCTFail("\(fx.id) SimpleMIDIPlayer rejected SMFWriter output: \(error)")
            } catch {
                // AVMIDIPlayer(data:soundBankURL: nil) can fail when no default sound bank
                // is available (e.g. some simulator / CI images). Environment, not a bug.
                unavailable.append("\(fx.id): \(error)")
            }
        }

        if !unavailable.isEmpty {
            throw XCTSkip(
                "AVMIDIPlayer(data:soundBankURL: nil) unavailable in this environment "
                    + "(no default sound bank?) for \(unavailable.count)/\(fixtures.count) fixtures: "
                    + unavailable.joined(separator: "; ")
            )
        }
    }

    // MARK: - (b) Sounding notes from SMF == expected.notes.csv rows

    func testSoundingNoteCountMatchesExpectedNotesCSV() throws {
        for fx in try Self.loadPlayableFixtures() {
            let smf = SMFWriter().write(symbols: fx.symbols)
            let sounding = try MIDINoteExtractor.notes(from: smf)

            XCTAssertEqual(
                sounding.count,
                fx.expectedNotes.count,
                "\(fx.id): sounding notes in SMF (\(sounding.count)) != expected.notes.csv rows (\(fx.expectedNotes.count))"
            )
            XCTAssertEqual(
                sounding.count,
                SymbolMIDIMapping.noteEvents(from: fx.symbols).count,
                "\(fx.id): SMF note-on count != SymbolMIDIMapping.noteEvents count"
            )

            // Round-trip sanity for the extractor itself: (tick, pitch, duration) multiset
            // matches the CSV. Staff is not recoverable (SMFWriter uses one note track).
            let got = sounding.map { TPD(tick: $0.tick, pitch: $0.pitch, duration: $0.duration) }.sorted()
            let want = fx.expectedNotes.map { TPD(tick: $0.tick, pitch: $0.pitch, duration: $0.duration) }.sorted()
            XCTAssertEqual(got, want, "\(fx.id): extracted (tick,pitch,duration) != expected.notes.csv")
        }
    }

    // MARK: - (c) Layer C highlight count == sounding notes

    func testLayerCHighlightCountEqualsSoundingNotes() throws {
        for fx in try Self.loadPlayableFixtures() {
            let smf = SMFWriter().write(symbols: fx.symbols)
            let sounding = try MIDINoteExtractor.notes(from: smf)
            let highlights = try Self.layerCHighlights(symbols: fx.symbols, smf: smf)

            // Hard (per TESTING.md): fail only if highlight count != sounding note count.
            XCTAssertEqual(
                highlights.noteLayout.count,
                sounding.count,
                "\(fx.id): highlight count (\(highlights.noteLayout.count)) != sounding notes (\(sounding.count)) [source=\(highlights.layoutSource.rawValue)]"
            )

            // Soft rule: every sounding note has a noteLayout entry OR source is midi-fallback.
            if highlights.layoutSource != .midiFallback {
                let covered = Set(highlights.noteLayout.compactMap { l in
                    l.midiNote.map { TP(tick: l.onsetTicks, pitch: $0) }
                })
                for n in sounding where !covered.contains(TP(tick: n.tick, pitch: n.pitch)) {
                    XCTFail("\(fx.id): sounding note \(n) has no noteLayout entry and source is \(highlights.layoutSource.rawValue)")
                }
            }

            // Index-aligned pitch/tick vs extracted MIDI after canonical (tick, pitch) ordering.
            // (Package helpers may order by tick/staff/pitch; SMFWriter drops staff, so compare
            // on the order both sides can reproduce.)
            let layoutTP = highlights.noteLayout.map { TP(tick: $0.onsetTicks, pitch: $0.midiNote ?? -1) }.sorted()
            let midiTP = sounding.map { TP(tick: $0.tick, pitch: $0.pitch) }.sorted()
            if layoutTP.count == midiTP.count {
                for (i, (l, m)) in zip(layoutTP, midiTP).enumerated() where l != m {
                    XCTFail("\(fx.id): highlight[\(i)] \(l) != midi[\(i)] \(m)")
                }
            }
        }
    }

    // MARK: - Layer C highlight source (single swap point)

    struct LayerCHighlights {
        var noteLayout: [NoteLayout]
        var layoutSource: LayoutSource
    }

    /// Layer C highlight source — keep this the ONE place that decides where highlights come from.
    ///
    /// Today: app-side midi-fallback — one `NoteLayout` per sounding note parsed from the SMF by
    /// `MIDINoteExtractor` (no coordinates; `pageRect == .null`; `symbolIndex` = sounding-note index).
    ///
    /// TODO(omr-core): when OMRHomrIOS exposes a public tokens→noteLayout helper (midi-fallback,
    /// one entry per sounding note from the same note-event list used for MIDI), replace this body
    /// with that single call and keep the assertions above: `noteLayout.count == sounding notes`
    /// OR `layoutSource == .midiFallback` (and the index-aligned pitch/tick check).
    static func layerCHighlights(symbols: [EncodedSymbol], smf: Data) throws -> LayerCHighlights {
        _ = symbols // consumed once the package helper lands
        let layout = try MIDINoteExtractor.notes(from: smf).enumerated().map { index, note in
            NoteLayout(
                symbolIndex: index,
                midiNote: note.pitch,
                onsetTicks: note.tick,
                durationTicks: note.duration,
                staffIndex: 0 // SMFWriter emits one note track; staff not recoverable from SMF
            )
        }
        return LayerCHighlights(noteLayout: layout, layoutSource: .midiFallback)
    }

    // MARK: - Fixture loading (mirrors package WriterOnlyFixtureTests, public API only)

    struct PlayableFixture {
        var id: String
        var symbols: [EncodedSymbol]
        var expectedNotes: [CSVNote]
    }

    struct CSVNote: Equatable {
        var tick: Int
        var pitch: Int
        var duration: Int
        var staff: Int
    }

    struct TP: Hashable, Comparable, CustomStringConvertible {
        var tick: Int
        var pitch: Int
        var description: String { "(t\(tick) p\(pitch))" }
        static func < (a: TP, b: TP) -> Bool { (a.tick, a.pitch) < (b.tick, b.pitch) }
    }

    struct TPD: Hashable, Comparable, CustomStringConvertible {
        var tick: Int
        var pitch: Int
        var duration: Int
        var description: String { "(\(tick),\(pitch),\(duration))" }
        static func < (a: TPD, b: TPD) -> Bool {
            (a.tick, a.pitch, a.duration) < (b.tick, b.pitch, b.duration)
        }
    }

    private struct TokenFile: Decodable {
        var status: String?
        var symbols: [TokenSymbol]?
    }

    private struct TokenSymbol: Decodable {
        var rhythm: String
        var pitch: String?
        var lift: String?
        var articulation: String?
        var slur: String?
        var position: String?
    }

    /// Fixture IDs never used for playback smoke even if tokens appear (Layer A oracle is
    /// owned by the 22/22 gate; skipped while awaiting export).
    static let excludedWhileAwaitingExport: Set<String> = ["oracle.c_scale_staff"]

    /// Every `fixtures/<id>/` with `expected.tokens.json` whose status is `complete` and has
    /// symbols. Dirs without tokens, stubs (e.g. `camera.deskew`), and the awaiting-export
    /// oracle are skipped and logged.
    static func loadPlayableFixtures() throws -> [PlayableFixture] {
        let root = try fixturesRoot()
        let fm = FileManager.default
        let ids = try fm.contentsOfDirectory(atPath: root.path).sorted()

        var out: [PlayableFixture] = []
        var skipped: [String] = []
        for id in ids {
            let dir = root.appendingPathComponent(id)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }

            let tokensURL = dir.appendingPathComponent("expected.tokens.json")
            guard fm.fileExists(atPath: tokensURL.path) else {
                skipped.append("\(id) (no expected.tokens.json)")
                continue
            }
            let file = try JSONDecoder().decode(TokenFile.self, from: Data(contentsOf: tokensURL))
            let status = file.status ?? "unknown"
            let rawSymbols = file.symbols ?? []

            if excludedWhileAwaitingExport.contains(id), status == "awaiting_oracle_export" || rawSymbols.isEmpty {
                skipped.append("\(id) (awaiting oracle export)")
                continue
            }
            guard status == "complete", !rawSymbols.isEmpty else {
                skipped.append("\(id) (status=\(status), symbols=\(rawSymbols.count))")
                continue
            }

            let notesURL = dir.appendingPathComponent("expected.notes.csv")
            guard fm.fileExists(atPath: notesURL.path) else {
                throw fixtureError("\(id) has complete tokens but no expected.notes.csv")
            }

            let symbols = rawSymbols.map { s in
                EncodedSymbol(
                    rhythm: s.rhythm,
                    pitch: s.pitch ?? EncodedSymbol.nonote,
                    lift: s.lift ?? EncodedSymbol.nonote,
                    articulation: s.articulation ?? EncodedSymbol.nonote,
                    slur: s.slur ?? EncodedSymbol.nonote,
                    position: s.position ?? EncodedSymbol.nonote
                )
            }
            out.append(PlayableFixture(id: id, symbols: symbols, expectedNotes: try loadNotesCSV(from: notesURL)))
        }

        print("PlaybackSmoke covered=\(out.map(\.id)) skipped=\(skipped)")

        guard !out.isEmpty else {
            throw fixtureError("no playable fixtures found under \(root.path); skipped=\(skipped)")
        }
        return out
    }

    /// `Tests/PlaybackSmokeFixtureTests.swift` → repo root → `fixtures/`.
    /// Works on simulator (host filesystem). On a physical device the source tree is not
    /// reachable, so skip rather than fail.
    static func fixturesRoot() throws -> URL {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
        let fixtures = repoRoot.appendingPathComponent("fixtures")
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: fixtures.path, isDirectory: &isDir), isDir.boolValue else {
            throw XCTSkip("repo-root fixtures/ not reachable at \(fixtures.path) (device run?)")
        }
        return fixtures
    }

    static func loadNotesCSV(from url: URL) throws -> [CSVNote] {
        let text = try String(contentsOf: url, encoding: .utf8)
        var out: [CSVNote] = []
        for (lineNo, raw) in text.components(separatedBy: .newlines).enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if lineNo == 0, line.lowercased().hasPrefix("tick") { continue }
            let cols = line.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard cols.count >= 4,
                  let tick = Int(cols[0]),
                  let pitch = Int(cols[1]),
                  let duration = Int(cols[2]),
                  let staff = Int(cols[3])
            else {
                throw fixtureError("bad CSV row in \(url.path): \(line)")
            }
            out.append(CSVNote(tick: tick, pitch: pitch, duration: duration, staff: staff))
        }
        return out
    }

    private static func fixtureError(_ message: String) -> NSError {
        NSError(domain: "PlaybackSmokeFixtureTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

/// Unit coverage for the app-side SMF note extractor on hand-built bytes (no OMR involved).
final class MIDINoteExtractorTests: XCTestCase {

    /// Format 0 single track: running status, note-on vel 0 as off, explicit 0x80 off,
    /// overlapping same pitch (FIFO), a meta event mid-track, and a hanging note.
    func testParsesRunningStatusVelocityZeroAndHangingNotes() throws {
        var track: [UInt8] = []
        track += [0x00, 0x90, 60, 100]      // t0   on C4 v100
        track += [0x00, 64, 90]             // t0   on E4 v90 (running status)
        track += [0x83, 0x60, 60, 0]        // t480 C4 vel0 → off (running status, delta 480)
        track += [0x00, 0xFF, 0x01, 0x02, 0x68, 0x69] // t480 text meta (cancels running status)
        track += [0x00, 0x80, 64, 0x40]     // t480 off E4
        track += [0x00, 0x90, 67, 80]       // t480 on G4 #1
        track += [0x60, 0x90, 67, 70]       // t576 on G4 #2 (overlap)
        track += [0x60, 0x80, 67, 0x40]     // t672 off → closes G4 #1 (FIFO)
        track += [0x60, 0x80, 67, 0x40]     // t768 off → closes G4 #2
        track += [0x00, 0x91, 72, 50]       // t768 on C5 ch1, never turned off
        track += [0x81, 0x70, 0xFF, 0x2F, 0x00] // t1008 end of track

        let data = Self.smf(format: 0, division: 480, tracks: [track])
        let notes = try MIDINoteExtractor.notes(from: data)

        XCTAssertEqual(notes, [
            MIDINote(tick: 0, pitch: 60, duration: 480, track: 0, channel: 0, velocity: 100),
            MIDINote(tick: 0, pitch: 64, duration: 480, track: 0, channel: 0, velocity: 90),
            MIDINote(tick: 480, pitch: 67, duration: 192, track: 0, channel: 0, velocity: 80),
            MIDINote(tick: 576, pitch: 67, duration: 192, track: 0, channel: 0, velocity: 70),
            MIDINote(tick: 768, pitch: 72, duration: 240, track: 0, channel: 1, velocity: 50),
        ])
        XCTAssertEqual(try MIDINoteExtractor.soundingNoteCount(in: data), 5)
    }

    func testConductorTrackHasNoNotesAndTrackIndexIsChunkIndex() throws {
        let conductor: [UInt8] = [0x00, 0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20, 0x00, 0xFF, 0x2F, 0x00]
        let notes: [UInt8] = [0x00, 0x90, 60, 80, 0x83, 0x60, 0x80, 60, 0x40, 0x00, 0xFF, 0x2F, 0x00]
        let data = Self.smf(format: 1, division: 480, tracks: [conductor, notes])
        let (header, parsed) = try MIDINoteExtractor.extract(from: data)
        XCTAssertEqual(header, .init(format: 1, trackCount: 2, division: 480))
        XCTAssertEqual(parsed, [MIDINote(tick: 0, pitch: 60, duration: 480, track: 1, channel: 0, velocity: 80)])
    }

    func testMatchesSMFWriterOutput() throws {
        let data = SMFWriter().write(notes: [
            SMFWriter.NoteEvent(midiNote: 60, onsetTicks: 0, durationTicks: 480),
            SMFWriter.NoteEvent(midiNote: 64, onsetTicks: 0, durationTicks: 480),
            SMFWriter.NoteEvent(midiNote: 67, onsetTicks: 480, durationTicks: 960),
        ])
        let notes = try MIDINoteExtractor.notes(from: data)
        XCTAssertEqual(notes.map(\.tick), [0, 0, 480])
        XCTAssertEqual(notes.map(\.pitch), [60, 64, 67])
        XCTAssertEqual(notes.map(\.duration), [480, 480, 960])
        XCTAssertEqual(Set(notes.map(\.track)), [1])
    }

    func testEmptyWriterOutputHasZeroSoundingNotes() throws {
        XCTAssertEqual(try MIDINoteExtractor.soundingNoteCount(in: SMFWriter().writeEmpty()), 0)
    }

    func testRejectsNonSMF() {
        XCTAssertThrowsError(try MIDINoteExtractor.notes(from: Data("not midi".utf8))) { error in
            XCTAssertEqual(error as? MIDINoteExtractor.ExtractError, .notSMF)
        }
    }

    private static func smf(format: UInt16, division: UInt16, tracks: [[UInt8]]) -> Data {
        func u16(_ v: UInt16) -> [UInt8] { [UInt8(v >> 8), UInt8(v & 0xFF)] }
        func u32(_ v: Int) -> [UInt8] {
            [UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
        }
        var bytes: [UInt8] = Array("MThd".utf8) + u32(6) + u16(format) + u16(UInt16(tracks.count)) + u16(division)
        for t in tracks {
            bytes += Array("MTrk".utf8) + u32(t.count) + t
        }
        return Data(bytes)
    }
}
