import Foundation
import CoreGraphics

/// Stable layout hit for highlight overlays. Geometry fields may be zero until
/// attention / midi-fallback layout is wired (post gate-1).
public struct NoteLayout: Equatable, Sendable {
    /// Zero-based index into the decoded symbol stream (notes only when layout is filled).
    public var symbolIndex: Int
    /// MIDI note number when known; nil for rests / non-pitch symbols.
    public var midiNote: Int?
    /// Onset in ticks (SMF 480 TPQ).
    public var onsetTicks: Int
    /// Duration in ticks.
    public var durationTicks: Int
    /// Approximate page-space rect for highlight; empty until layout source is ready.
    public var pageRect: CGRect
    /// Staff index within the page (0-based). Staff-only gate-1 uses 0.
    public var staffIndex: Int

    public init(
        symbolIndex: Int,
        midiNote: Int? = nil,
        onsetTicks: Int = 0,
        durationTicks: Int = 0,
        pageRect: CGRect = .null,
        staffIndex: Int = 0
    ) {
        self.symbolIndex = symbolIndex
        self.midiNote = midiNote
        self.onsetTicks = onsetTicks
        self.durationTicks = durationTicks
        self.pageRect = pageRect
        self.staffIndex = staffIndex
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
