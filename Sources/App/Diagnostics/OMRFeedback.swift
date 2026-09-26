import CoreGraphics
import Foundation
import OMRHomrIOS

/// App-side, Codable view of one recognized sounding note (from the package's `NoteLayout`).
struct RecognizedNote: Codable, Hashable, Identifiable, Sendable {
    var id: Int { noteIndex }
    var noteIndex: Int
    var symbolIndex: Int
    var staffIndex: Int
    var midiNote: Int?
    var onsetTicks: Int
    var durationTicks: Int
    /// Page-space box in input-image pixels; nil when the layout has no box (midi-fallback).
    var box: Box?

    struct Box: Codable, Hashable, Sendable {
        var x, y, width, height: Double
        init(_ r: CGRect) { x = r.minX; y = r.minY; width = r.width; height = r.height }
        var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    }

    var rect: CGRect? { box?.cgRect }

    init(noteIndex: Int, symbolIndex: Int, staffIndex: Int, midiNote: Int?, onsetTicks: Int, durationTicks: Int, rect: CGRect? = nil) {
        self.noteIndex = noteIndex
        self.symbolIndex = symbolIndex
        self.staffIndex = staffIndex
        self.midiNote = midiNote
        self.onsetTicks = onsetTicks
        self.durationTicks = durationTicks
        self.box = rect.map { Box($0) }
    }

    init(_ l: NoteLayout) {
        self.init(
            noteIndex: l.noteIndex, symbolIndex: l.symbolIndex, staffIndex: l.staffIndex, midiNote: l.midiNote,
            onsetTicks: l.onsetTicks, durationTicks: l.durationTicks, rect: l.hasBox ? l.pageRect : nil
        )
    }

    var pitchName: String { midiNote.map(Self.pitchName) ?? "?" }
    var durationName: String { Self.durationName(ticks: durationTicks) }

    /// MIDI 60 → "C4".
    static func pitchName(_ midi: Int) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        return "\(names[((midi % 12) + 12) % 12])\(midi / 12 - 1)"
    }

    /// 480 TPQ ticks → "quarter", "dotted half", … or "N ticks".
    static func durationName(ticks: Int, tpq: Int = 480) -> String {
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
    static func fromSymbols(_ symbols: [EncodedSymbol]) -> [RecognizedNote] {
        NoteLayout.midiFallback(from: SymbolMIDIMapping.orderedNoteEvents(from: symbols)).map(RecognizedNote.init)
    }
}

/// What the Result / Compare screens show and what feedback refers to.
struct RecognitionDetails: Equatable, Sendable {
    var midi: Data
    var notes: [RecognizedNote]
    var staffCount: Int
    var warnings: [String]
    var layoutSource: String
    var ms: Double

    init(midi: Data, notes: [RecognizedNote], staffCount: Int, warnings: [String], layoutSource: String, ms: Double) {
        self.midi = midi
        self.notes = notes
        self.staffCount = staffCount
        self.warnings = warnings
        self.layoutSource = layoutSource
        self.ms = ms
    }

    init(_ r: ParseSheetMusicResult, ms: Double) {
        self.init(
            midi: r.midi, notes: r.noteLayout.map(RecognizedNote.init), staffCount: r.staffCount,
            warnings: r.warnings, layoutSource: r.layoutSource.rawValue, ms: ms
        )
    }

    var hasBoxes: Bool { notes.contains { $0.rect != nil } }
}

/// User's OMR accuracy feedback for one capture (stored as a `feedback` log event).
struct OMRFeedback: Codable, Equatable, Sendable {
    enum Verdict: String, Codable, CaseIterable, Sendable {
        case accurate
        case partlyWrong = "partly_wrong"
        case wrong

        var label: String {
            switch self {
            case .accurate: return "Accurate"
            case .partlyWrong: return "Partly wrong"
            case .wrong: return "Wrong"
            }
        }
    }

    struct StaffVerdict: Codable, Equatable, Sendable {
        var staffIndex: Int
        var verdict: Verdict
    }

    struct WrongNote: Codable, Equatable, Sendable {
        var noteIndex: Int
        var staffIndex: Int
        var pitch: String
    }

    /// Capture file name (`20260926-130501-123.jpg`) or `gate1/staff.png`.
    var captureName: String
    var verdict: Verdict?
    var staffVerdicts: [StaffVerdict] = []
    var wrongNotes: [WrongNote] = []
    var note: String = ""
    var staffCount: Int
    var noteCount: Int
    var layoutSource: String?
    var date: Date = Date()

    var isEmpty: Bool { verdict == nil && staffVerdicts.isEmpty && wrongNotes.isEmpty && note.isEmpty }

    var summary: String {
        var s = "feedback \(captureName): \(verdict?.label ?? "no verdict")"
        if !wrongNotes.isEmpty { s += ", \(wrongNotes.count) wrong note\(wrongNotes.count == 1 ? "" : "s")" }
        return s
    }

    // MARK: - Log event round-trip

    static let payloadKey = "feedback_json"

    func event() throws -> DiagnosticsEvent {
        let json = String(decoding: try DiagnosticsLog.encoder.encode(self), as: UTF8.self)
        return DiagnosticsEvent(
            level: .info, category: .feedback, message: summary,
            payload: [Self.payloadKey: json, "capture": captureName]
        )
    }

    init(captureName: String, verdict: Verdict? = nil, staffVerdicts: [StaffVerdict] = [], wrongNotes: [WrongNote] = [],
         note: String = "", staffCount: Int, noteCount: Int, layoutSource: String? = nil, date: Date = Date()) {
        self.captureName = captureName
        self.verdict = verdict
        self.staffVerdicts = staffVerdicts
        self.wrongNotes = wrongNotes
        self.note = note
        self.staffCount = staffCount
        self.noteCount = noteCount
        self.layoutSource = layoutSource
        self.date = date
    }

    init?(event: DiagnosticsEvent) {
        guard event.category == .feedback, let json = event.payload?[Self.payloadKey],
              let f = try? DiagnosticsLog.decoder.decode(OMRFeedback.self, from: Data(json.utf8)) else { return nil }
        self = f
    }
}
