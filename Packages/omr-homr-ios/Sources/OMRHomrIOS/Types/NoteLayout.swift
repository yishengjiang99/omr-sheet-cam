import Foundation
import CoreGraphics

/// Stable layout hit for highlight overlays.
///
/// One entry per **sounding** MIDI note (rests produce none; each chord member gets its own
/// entry with the shared onset). When built by `OMRHomrIOS.renderTokens`, `noteLayout[k]`
/// describes the k-th note-on in the SMF note track (same shared, sorted note-event list).
///
/// `pageRect` is `CGRect.null` when no real box is known (`layoutSource == .midiFallback`);
/// coordinates are never fabricated.
public struct NoteLayout: Equatable, Sendable {
    /// Zero-based index into the decoded symbol stream (the `note_*` symbol that sounded).
    public var symbolIndex: Int
    /// MIDI note number when known; nil for rests / non-pitch symbols.
    public var midiNote: Int?
    /// Onset in ticks (SMF 480 TPQ).
    public var onsetTicks: Int
    /// Duration in ticks.
    public var durationTicks: Int
    /// Page-space rect for highlight; `.null` when no box is available (midi-fallback).
    public var pageRect: CGRect
    /// Staff index within the page (0-based, 0 = top staff). Staff-only gate-1 uses 0.
    public var staffIndex: Int
    /// Zero-based index of this entry in the sorted sounding-note list (== its array index
    /// in `noteLayout`, == ordinal of its note-on in the SMF note track).
    public var noteIndex: Int

    public init(
        symbolIndex: Int,
        midiNote: Int? = nil,
        onsetTicks: Int = 0,
        durationTicks: Int = 0,
        pageRect: CGRect = .null,
        staffIndex: Int = 0,
        noteIndex: Int = 0
    ) {
        self.symbolIndex = symbolIndex
        self.midiNote = midiNote
        self.onsetTicks = onsetTicks
        self.durationTicks = durationTicks
        self.pageRect = pageRect
        self.staffIndex = staffIndex
        self.noteIndex = noteIndex
    }

    /// True when `pageRect` carries a real box (not `.null` / empty).
    public var hasBox: Bool {
        !pageRect.isNull && !pageRect.isEmpty
    }

    /// Box-less layout (one entry per sounding note) from the shared ordered note list.
    ///
    /// Pass the output of `SymbolMIDIMapping.orderedNoteEvents(from:)` so entry order matches
    /// the MIDI note order. `noteIndex` is the position in `events`; `pageRect` is `.null`.
    public static func midiFallback(
        from events: [SymbolMIDIMapping.SourcedNoteEvent]
    ) -> [NoteLayout] {
        events.enumerated().map { index, sourced in
            NoteLayout(
                symbolIndex: sourced.symbolIndex,
                midiNote: Int(sourced.event.midiNote),
                onsetTicks: sourced.event.onsetTicks,
                durationTicks: sourced.event.durationTicks,
                pageRect: .null,
                staffIndex: sourced.event.staff,
                noteIndex: index
            )
        }
    }
}

/// Where `noteLayout` coordinates came from.
public enum LayoutSource: String, Equatable, Sendable {
    case attention
    case midiFallback = "midi-fallback"
}

/// Result of `parseSheetMusicWithLayout`.
public struct ParseSheetMusicResult: Equatable, Sendable {
    public var midi: Data
    public var noteLayout: [NoteLayout]
    public var layoutSource: LayoutSource
    public var staffCount: Int
    public var warnings: [String]

    public init(
        midi: Data,
        noteLayout: [NoteLayout],
        layoutSource: LayoutSource,
        staffCount: Int,
        warnings: [String]
    ) {
        self.midi = midi
        self.noteLayout = noteLayout
        self.layoutSource = layoutSource
        self.staffCount = staffCount
        self.warnings = warnings
    }
}

/// Input to the public parse entry point. Gate-1 uses a single staff image.
public struct ParseSheetMusicInput: Sendable {
    /// Staff (or page) image bytes — PNG/JPEG. Full-page geometry is out of scope for gate-1.
    public var imageData: Data
    /// When true, run staff-only encoder→decoder path (gate-1). Full-page SegNet is later.
    public var staffOnly: Bool

    public init(imageData: Data, staffOnly: Bool = true) {
        self.imageData = imageData
        self.staffOnly = staffOnly
    }
}
