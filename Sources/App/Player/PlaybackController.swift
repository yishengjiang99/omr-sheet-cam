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
            try player.load(midi: midi)
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
