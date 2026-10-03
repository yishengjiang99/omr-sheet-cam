import CoreGraphics
import Foundation
import SF2Player

/// Where each recognized note sits on the scan photo, saved next to the scan's MIDI as
/// `<stem>.layout.json` (PlaylistStore). The Player's Sheet mode draws `notes[].box` over the
/// capture (`captureName`) and highlights the ones `SF2MIDIPlayer.activeNoteIDs` reports
/// (ids = `noteIndex`, ticks = the scan MIDI's own ticks).
struct ScanLayout: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version: Int = ScanLayout.currentVersion
    /// Pixel size of the recognized (upright) photo; boxes are in these pixels.
    var imageWidth: Int
    var imageHeight: Int
    var captureName: String?
    var staffCount: Int
    var layoutSource: String
    var notes: [RecognizedNote]

    init(imageWidth: Int, imageHeight: Int, captureName: String?, staffCount: Int, layoutSource: String, notes: [RecognizedNote]) {
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.captureName = captureName
        self.staffCount = staffCount
        self.layoutSource = layoutSource
        self.notes = notes
    }

    /// nil when no note has a box (midi-fallback layouts can't be drawn).
    init?(_ d: RecognitionDetails, imageWidth: Int, imageHeight: Int, captureName: String?) {
        guard d.hasBoxes, imageWidth > 0, imageHeight > 0 else { return nil }
        self.init(imageWidth: imageWidth, imageHeight: imageHeight, captureName: captureName, staffCount: d.staffCount,
                  layoutSource: d.layoutSource, notes: d.notes)
    }

    var boxedNotes: [RecognizedNote] { notes.filter { $0.box != nil } }
    var imageSize: CGSize { CGSize(width: imageWidth, height: imageHeight) }

    /// For `SF2MIDIPlayer.notePositions` (end = onset + duration, at least 1 tick).
    var notePositions: [SF2NotePosition] {
        notes.map { SF2NotePosition(id: $0.noteIndex, startTick: $0.onsetTicks, endTick: $0.onsetTicks + max(1, $0.durationTicks)) }
    }

    /// Nearest boxed note to `point` (image pixels) within `maxDistance` pixels of its box.
    func note(near point: CGPoint, maxDistance: Double) -> RecognizedNote? {
        var best: RecognizedNote?
        var bestD = maxDistance
        for n in notes {
            guard let r = n.rect else { continue }
            let dx = max(r.minX - point.x, 0, point.x - r.maxX)
            let dy = max(r.minY - point.y, 0, point.y - r.maxY)
            let d = (dx * dx + dy * dy).squareRoot()
            if d < bestD || (d == bestD && best == nil) { bestD = d; best = n }
        }
        return best
    }

    /// The first (lowest noteIndex) of `ids` that has a box; the auto-scroll target.
    func scrollTarget(for ids: Set<Int>) -> RecognizedNote? {
        notes.filter { ids.contains($0.noteIndex) && $0.box != nil }.min { $0.noteIndex < $1.noteIndex }
    }

    /// `ode.mid` -> `ode.layout.json`.
    static func sidecarName(forMIDI fileName: String) -> String {
        "\((fileName as NSString).deletingPathExtension).layout.json"
    }

    func encoded() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return try e.encode(self)
    }

    static func decode(_ data: Data) throws -> ScanLayout { try JSONDecoder().decode(ScanLayout.self, from: data) }
}
