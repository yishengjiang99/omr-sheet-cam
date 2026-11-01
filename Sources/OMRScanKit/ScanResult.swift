import CoreGraphics
import Foundation
@_exported import OMRHomrIOS

/// App-side, Codable view of one recognized sounding note (from the package's `NoteLayout`).
public struct RecognizedNote: Codable, Hashable, Identifiable, Sendable {
    public var id: Int { noteIndex }
    public var noteIndex: Int
    public var symbolIndex: Int
    public var staffIndex: Int
    public var midiNote: Int?
    public var onsetTicks: Int
    public var durationTicks: Int
    /// Page-space box in input-image pixels; nil when the layout has no box (midi-fallback).
    public var box: Box?

    public struct Box: Codable, Hashable, Sendable {
        var x, y, width, height: Double
        init(_ r: CGRect) { x = r.minX; y = r.minY; width = r.width; height = r.height }
        var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    }

    public var rect: CGRect? { box?.cgRect }

    public init(noteIndex: Int, symbolIndex: Int, staffIndex: Int, midiNote: Int?, onsetTicks: Int, durationTicks: Int, rect: CGRect? = nil) {
        self.noteIndex = noteIndex
        self.symbolIndex = symbolIndex
        self.staffIndex = staffIndex
        self.midiNote = midiNote
        self.onsetTicks = onsetTicks
        self.durationTicks = durationTicks
        self.box = rect.map { Box($0) }
    }

    public init(_ l: NoteLayout) {
        self.init(
            noteIndex: l.noteIndex, symbolIndex: l.symbolIndex, staffIndex: l.staffIndex, midiNote: l.midiNote,
            onsetTicks: l.onsetTicks, durationTicks: l.durationTicks, rect: l.hasBox ? l.pageRect : nil
        )
    }

    public var pitchName: String { midiNote.map(Self.pitchName) ?? "?" }
    public var durationName: String { Self.durationName(ticks: durationTicks) }

    /// MIDI 60 → "C4".
    public static func pitchName(_ midi: Int) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        return "\(names[((midi % 12) + 12) % 12])\(midi / 12 - 1)"
    }

    /// 480 TPQ ticks → "quarter", "dotted half", … or "N ticks".
    public static func durationName(ticks: Int, tpq: Int = 480) -> String {
        let table: [(Int, String)] = [
            (tpq * 4, "whole"), (tpq * 2, "half"), (tpq, "quarter"), (tpq / 2, "eighth"),
            (tpq / 4, "16th"), (tpq / 8, "32nd"),
        ]
        for (t, n) in table {
            if ticks == t { return n }
            if ticks == t * 3 / 2 { return "dotted \(n)" }
        }
        return "\(ticks) ticks"
    }

    /// Box-less notes from decoded symbols (same ordering as the package's `noteLayout`).
    public static func fromSymbols(_ symbols: [EncodedSymbol]) -> [RecognizedNote] {
        NoteLayout.midiFallback(from: SymbolMIDIMapping.orderedNoteEvents(from: symbols)).map(RecognizedNote.init)
    }
}

/// What the Result / Compare screens show and what feedback refers to.
public struct RecognitionDetails: Equatable, Sendable {
    public var midi: Data
    public var notes: [RecognizedNote]
    public var staffCount: Int
    public var warnings: [String]
    public var layoutSource: String
    public var ms: Double
    /// Stage timings and per-staff token counts for telemetry; nil for fakes.
    public var diagnostics: PageDiagnostics?

    public init(midi: Data, notes: [RecognizedNote], staffCount: Int, warnings: [String], layoutSource: String, ms: Double,
                diagnostics: PageDiagnostics? = nil) {
        self.diagnostics = diagnostics
        self.midi = midi
        self.notes = notes
        self.staffCount = staffCount
        self.warnings = warnings
        self.layoutSource = layoutSource
        self.ms = ms
    }

    public init(_ r: ParseSheetMusicResult, ms: Double) {
        self.init(
            midi: r.midi, notes: r.noteLayout.map(RecognizedNote.init), staffCount: r.staffCount,
            warnings: r.warnings, layoutSource: r.layoutSource.rawValue, ms: ms
        )
    }

    public var hasBoxes: Bool { notes.contains { $0.rect != nil } }
}

/// Per-page measurements the package records: stage timings and per-staff decoder symbol counts
/// (raw vs post-filter, grand-staff flag, voice, row, encode+decode ms).
public struct PageDiagnostics: Equatable, Sendable {
    public struct Stage: Equatable, Sendable { public var name: String; public var ms: Double }
    public struct StaffSymbols: Equatable, Sendable {
        public var raw: Int, filtered: Int, isGrandstaff: Bool, voice: Int, row: Int
    }
    public var stages: [Stage]
    public var staffSymbols: [StaffSymbols]
    /// Per staff (same order as `staffSymbols`): encoder + decoder ms from the stage timings.
    public var perStaffMs: [Double]

    init(_ out: PageParseOutput) {
        stages = out.stages.map { Stage(name: $0.name, ms: $0.ms) }
        staffSymbols = out.staffSymbols.map { StaffSymbols(raw: $0.raw, filtered: $0.filtered, isGrandstaff: $0.isGrandstaff, voice: $0.voice, row: $0.row) }
        var per = [Double](repeating: 0, count: out.staffSymbols.count)
        for s in out.stages where s.name.hasPrefix("decode_s") {
            let rest = s.name.dropFirst("decode_s".count)
            guard let sep = rest.firstIndex(of: "_"), let i = Int(rest[..<sep]), per.indices.contains(i) else { continue }
            per[i] += s.ms
        }
        perStaffMs = per
    }
}
