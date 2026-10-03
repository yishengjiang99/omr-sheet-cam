import Combine
import Foundation
import SF2Player
import UIKit

/// App-wide playback: one `SF2MIDIPlayer`, the current item, prev/next through the Library.
/// Keeps playing when you leave the Player (Library shows a mini-player). Applies the persisted
/// instrument / tempo (`AppSettings`). Transport events go to `DiagnosticsLog` (playback).
@MainActor
final class PlaybackController: ObservableObject {
    static let shared = PlaybackController(store: .shared, settings: .shared)

    let player = SF2MIDIPlayer()
    let store: PlaylistStore
    let settings: AppSettings
    @Published private(set) var current: PlayerRoute?
    @Published private(set) var ready = false
    @Published private(set) var status = ""
    /// Note boxes of the loaded scan (`<stem>.layout.json`), nil for samples / ad-hoc MIDI /
    /// scans saved before Sheet mode. Drives `player.notePositions`.
    @Published private(set) var layout: ScanLayout?
    /// The scan photo `layout` refers to (loaded once per song).
    @Published private(set) var sheetImage: UIImage?
    /// A–B loop being set: A (seconds) is marked, waiting for B.
    @Published private(set) var pendingLoopStart: Double?
    /// Notes tapped as A / B in Sheet mode (badges).
    @Published private(set) var loopNoteIDs: [Int: String] = [:]
    private var loadTask: Task<Void, Never>?
    private var bag: Set<AnyCancellable> = []

    init(store: PlaylistStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
        player.tempoScale = settings.tempo
        player.program = settings.instrument.program
        settings.$tempo.removeDuplicates().sink { [weak self] t in self?.player.tempoScale = t }.store(in: &bag)
        settings.$instrument.removeDuplicates().sink { [weak self] i in
            guard let self, self.player.program != i.program else { return }
            self.player.program = i.program
            self.log("instrument", ["to": i.name])
        }.store(in: &bag)
        player.onFinished = { [weak self] in
            guard let self else { return }
            self.log("finished", [:])
            if let next = self.autoNextRoute() { self.open(next, reason: "auto-next") }
        }
    }

    /// The route to auto-advance to when the current item finishes, or nil to stop.
    /// Only non-nil in playlist mode (`advanceOnFinish` set at open time); a
    /// just-scanned sheet plays once and stops.
    func autoNextRoute() -> PlayerRoute? {
        guard current?.advanceOnFinish == true, let n = nextRoute else { return nil }
        var r = n
        r.advanceOnFinish = true
        return r
    }

    // MARK: Current item

    var entryID: String? {
        if case let .playlist(id)? = current?.item { return id }
        return nil
    }

    var entry: PlaylistEntry? { entryID.flatMap { store.entry(id: $0) } }
    var title: String { entry?.title ?? current?.title ?? "Nothing playing" }
    var isFromLibrary: Bool { entryID != nil }
    var subtitle: String {
        let source = entry.map { $0.source == .sample ? "Samples" : "Your scans" } ?? "Now playing"
        return "\(source) · \(settings.instrument.name)"
    }

    /// Scan photo for artwork (Documents/captures/<captureName>), if still on disk.
    var artwork: UIImage? { entry.flatMap(Self.artwork(for:)) }

    static func artwork(for e: PlaylistEntry) -> UIImage? {
        guard let name = e.captureName, let dir = try? CaptureStore.defaultDirectory() else { return nil }
        return UIImage(contentsOfFile: dir.appendingPathComponent(name).path)
    }

    /// Share item for what is loaded: the Library entry, or the ad-hoc MIDI bytes.
    var export: MIDIExport? {
        if let e = entry { return store.export(for: e) }
        if case let .midi(d)? = current?.item, !d.isEmpty { return MIDIExport(title: title, source: .data(d)) }
        return nil
    }

    /// Transpose in semitones for the loaded song (reset to 0 when another song loads).
    func setTranspose(_ semitones: Int) {
        guard semitones != player.transpose else { return }
        player.transpose = semitones
        log("transpose", ["to": "\(player.transpose)"])
    }

    nonisolated static func keyLabel(_ semitones: Int) -> String {
        semitones == 0 ? "Key 0" : String(format: "Key %+d", semitones)
    }

    nonisolated static let transposeChoices = Array(-12 ... 12)

    /// Menu row: "Original key", "+1 semitone", "-12 semitones".
    nonisolated static func transposeName(_ t: Int) -> String {
        t == 0 ? "Original key" : "\(t > 0 ? "+" : "")\(t) semitone\(abs(t) == 1 ? "" : "s")"
    }

    var previousRoute: PlayerRoute? { entryID.flatMap { store.neighbor(of: $0, offset: -1) }.map { PlayerRoute(entry: $0) } }
    var nextRoute: PlayerRoute? { entryID.flatMap { store.neighbor(of: $0, offset: 1) }.map { PlayerRoute(entry: $0) } }

    // MARK: Transport

    /// Loads `route` (unless it is already loaded) and starts playing if `route.autoplay`.
    func open(_ route: PlayerRoute, reason: String = "open") {
        if let current, current.item == route.item, ready {
            if route.autoplay && !player.isPlaying { play(auto: true) }
            return
        }
        log("track_change", ["reason": reason, "to": route.title])
        current = route
        loadTask?.cancel()
        loadTask = Task { await load(route) }
    }

    func togglePlay() {
        if player.isPlaying {
            player.pause()
            log("pause", [:])
        } else {
            play(auto: false)
        }
    }

    func next() {
        if var n = nextRoute {
            n.advanceOnFinish = true // manual list navigation engages playlist mode
            open(n, reason: "next")
        }
    }

    /// Restarts if more than 3 s in (or first in the list), else goes to the previous item.
    func previous() {
        if player.position.seconds > 3 || previousRoute == nil {
            player.seek(to: 0)
            log("restart", [:])
        } else if var p = previousRoute {
            p.advanceOnFinish = true // manual list navigation engages playlist mode
            open(p, reason: "previous")
        }
    }

    func seek(to s: Double) {
        player.seek(to: s)
        log("seek", ["to": String(format: "%.2f", s)])
    }

    // MARK: Practice: A–B loop, hands

    /// Marks A, then B (B before A swaps them). With a loop on, starts a new A.
    /// `endSeconds`: where B ends when marking a tapped note (its release), else `seconds`.
    func markLoopPoint(at seconds: Double, noteID: Int? = nil, endSeconds: Double? = nil) {
        if player.loop != nil { player.clearLoop(); pendingLoopStart = nil; loopNoteIDs = [:] }
        if let a = pendingLoopStart {
            let b = endSeconds ?? seconds
            pendingLoopStart = nil
            player.setLoop(start: min(a, seconds), end: max(a, b))
            if let noteID { loopNoteIDs[noteID] = "B" }
            if player.loop == nil { loopNoteIDs = [:] }
            log("loop", ["a": String(format: "%.2f", player.loop?.start ?? a), "b": String(format: "%.2f", player.loop?.end ?? b)])
        } else {
            pendingLoopStart = seconds
            loopNoteIDs = noteID.map { [$0: "A"] } ?? [:]
        }
    }

    /// Sheet tap in loop mode: A = the note's onset, B = the end of the tapped note.
    func markLoopPoint(note: RecognizedNote) {
        guard let song = player.song else { return }
        markLoopPoint(at: song.tickToSec(note.onsetTicks), noteID: note.noteIndex,
                      endSeconds: song.tickToSec(note.onsetTicks + max(1, note.durationTicks)))
    }

    func clearLoop() {
        player.clearLoop()
        pendingLoopStart = nil
        loopNoteIDs = [:]
        log("loop_clear", [:])
    }

    /// Notes (layout ids) whose onset is inside the loop, for the Sheet tint.
    var loopNoteSet: Set<Int> {
        guard let loop = player.loop, let song = player.song, let layout else { return [] }
        return Set(layout.notes.filter {
            let t = song.tickToSec($0.onsetTicks)
            return t >= loop.start - 1e-6 && t < loop.end - 1e-6
        }.map(\.noteIndex))
    }

    /// UI names for note tracks: an unnamed two-staff scan reads as right / left hand.
    nonisolated static func handNames(_ tracks: [SF2TrackInfo]) -> [Int: String] {
        let generic = tracks.allSatisfy { $0.name.hasPrefix("Track ") || $0.name.isEmpty }
        if tracks.count == 2 && generic {
            return [tracks[0].index: "Right hand", tracks[1].index: "Left hand"]
        }
        return Dictionary(uniqueKeysWithValues: tracks.enumerated().map { i, t in
            (t.index, generic ? "Staff \(i + 1)" : t.name)
        })
    }

    /// Chip text: "Both hands", "Right hand only", "Left hand muted", "2 of 3 parts".
    nonisolated static func handsLabel(_ tracks: [SF2TrackInfo], muted: Set<Int>) -> String {
        let names = handNames(tracks)
        let playing = tracks.filter { !muted.contains($0.index) }
        if playing.count == tracks.count { return tracks.count == 2 ? "Both hands" : "All parts" }
        if playing.isEmpty { return "All muted" }
        if playing.count == 1, let n = names[playing[0].index] { return "\(n) only" }
        return "\(playing.count) of \(tracks.count) parts"
    }

    func solo(_ track: Int?) {
        player.solo(track)
        log("hands", ["muted": player.mutedTracks.sorted().map(String.init).joined(separator: ",")])
    }

    func setMuted(_ track: Int, _ muted: Bool) {
        player.setMuted(track, muted)
        log("hands", ["muted": player.mutedTracks.sorted().map(String.init).joined(separator: ",")])
    }

    /// Sheet mode tap: jump to a note's onset (keeps playing / paused state).
    func seek(toNote note: RecognizedNote) {
        player.seek(toTick: note.onsetTicks)
        log("seek_note", ["note": "\(note.noteIndex)", "tick": "\(note.onsetTicks)"])
    }

    /// Capture named by the layout (else the entry's artwork); nil without a layout.
    static func sheetImage(for layout: ScanLayout?, entry: PlaylistEntry?) -> UIImage? {
        guard let layout else { return nil }
        if let name = layout.captureName, let dir = try? CaptureStore.defaultDirectory(),
           let img = UIImage(contentsOfFile: dir.appendingPathComponent(name).path) { return img }
        return entry.flatMap(artwork(for:))
    }

    func stop() {
        if player.isPlaying { log("stop", [:]) }
        player.stop()
    }

    private func play(auto: Bool) {
        player.play()
        log(player.isPlaying ? "play" : "play_failed", auto ? ["auto": "1"] : [:])
    }

    private func load(_ route: PlayerRoute) async {
        ready = false
        layout = nil
        sheetImage = nil
        pendingLoopStart = nil
        loopNoteIDs = [:]
        player.notePositions = []
        status = "Loading…"
        do {
            let sf = try await BundledSoundFont.load()
            guard !Task.isCancelled, current?.item == route.item else { return }
            let midi: Data
            switch route.item {
            case let .midi(d): midi = d
            case let .playlist(id):
                guard let e = store.entry(id: id) else { throw PlaylistStore.StoreError.notFound(id) }
                midi = try store.midiData(for: e)
            }
            try player.load(soundFont: sf)
            if player.transpose != 0 { player.transpose = 0 } // per song
            try player.load(midi: midi)
            var lay: ScanLayout?
            var entry: PlaylistEntry?
            if case let .playlist(id) = route.item, let e = store.entry(id: id) { entry = e; lay = store.layout(for: e) }
            let img = Self.sheetImage(for: lay, entry: entry)
            if img == nil { lay = nil } // nothing to draw on
            layout = lay
            sheetImage = img
            player.notePositions = lay?.notePositions ?? []
            ready = true
            status = ""
            log("load", ["bytes": "\(midi.count)", "duration": String(format: "%.2f", player.duration)])
            if route.autoplay { play(auto: true) }
        } catch {
            ready = false
            status = "Can't play this: \(error)"
            DiagnosticsLog.shared.record(error: error, category: .playback, context: "player load \(route.title)")
        }
    }

    private func log(_ kind: String, _ extra: [String: String]) {
        var p = extra
        p["kind"] = kind
        p["track"] = entryID ?? "adhoc"
        p["position"] = String(format: "%.2f", player.position.seconds)
        let details = extra.sorted { $0.key < $1.key }.map { kv in "\(kv.key)=\(kv.value)" }.joined(separator: " ")
        let message = details.isEmpty ? "player \(kind): \(title)" : "player \(kind): \(title) \(details)"
        DiagnosticsLog.shared.record(.info, .playback, message, payload: p)
    }
}
