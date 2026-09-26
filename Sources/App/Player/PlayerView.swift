import SF2Player
import SwiftUI

/// Bundled GeneralUser GS (models.lock -> scripts/fetch-models -> "Bundle ONNX models" phase ->
/// `<App>.app/models/GeneralUser-GS.sf2`), parsed once per process off the main thread.
@MainActor
enum BundledSoundFont {
    static let fileName = "GeneralUser-GS.sf2"
    private static var task: Task<SF2SoundFont, Error>?

    enum LoadError: Error, CustomStringConvertible {
        case missing
        var description: String { "GeneralUser-GS.sf2 not bundled (run scripts/fetch-models)" }
    }

    static func url(bundle: Bundle = .main) -> URL? {
        if let u = bundle.url(forResource: "GeneralUser-GS", withExtension: "sf2", subdirectory: "models") { return u }
        // Test-only builds: models supplied at run time (OMR_MODELS_DIR), like ModelWarmup.
        if let dir = ProcessInfo.processInfo.environment["OMR_MODELS_DIR"] {
            let u = URL(fileURLWithPath: dir).appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return nil
    }

    static func load() async throws -> SF2SoundFont {
        if let task { return try await task.value }
        guard let url = url() else { throw LoadError.missing }
        let t = Task { try await SF2SoundFont.load(contentsOf: url) }
        task = t
        do { return try await t.value } catch { task = nil; throw error }
    }
}

/// SF2 player: play/pause, seek (elapsed / total), prev/next through the playlist, tempo, live
/// output level meter. Opened on a playlist entry (Result "Play", Playlist, samples) or on ad-hoc
/// SMF bytes. Transport events are recorded in `DiagnosticsLog` (category playback).
struct PlayerView: View {
    @ObservedObject private var store: PlaylistStore
    @StateObject private var player = SF2MIDIPlayer()
    @State private var current: PlayerRoute
    @State private var status = "Loading SoundFont…"
    @State private var ready = false
    @State private var scrub: Double?
    @State private var showPlaylist = false

    init(route: PlayerRoute, store: PlaylistStore = .shared) {
        _current = State(initialValue: route)
        _store = ObservedObject(wrappedValue: store)
    }

    init(midi: Data, title: String = "Player", store: PlaylistStore = .shared) {
        self.init(route: PlayerRoute(midi: midi, title: title, autoplay: false), store: store)
    }

    private var entryID: String? {
        if case let .playlist(id) = current.item { return id }
        return nil
    }

    private var title: String { entryID.flatMap { store.entry(id: $0)?.title } ?? current.title }
    private var previous: PlayerRoute? { entryID.flatMap { store.neighbor(of: $0, offset: -1) }.map { PlayerRoute(entry: $0) } }
    private var next: PlayerRoute? { entryID.flatMap { store.neighbor(of: $0, offset: 1) }.map { PlayerRoute(entry: $0) } }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline).lineLimit(2).accessibilityIdentifier("player.title")
                    Text(status).font(.footnote).foregroundStyle(ready ? Color.secondary : Color.orange)
                }
            }
            Section("Playback") {
                transport
                Slider(value: Binding(get: { scrub ?? player.position.seconds }, set: { scrub = $0 }),
                       in: 0 ... max(player.duration, 0.01)) { editing in
                    if !editing, let s = scrub {
                        player.seek(to: s)
                        scrub = nil
                        logEvent("seek", ["to": String(format: "%.2f", s)])
                    }
                }
                .disabled(!ready)
                .accessibilityIdentifier("player.seek")
                HStack {
                    Text(Self.clock(scrub ?? player.position.seconds)).accessibilityIdentifier("player.elapsed")
                    Spacer()
                    Text("tick \(Int(player.position.tick))").foregroundStyle(.tertiary)
                    Spacer()
                    Text(Self.clock(player.duration)).accessibilityIdentifier("player.total")
                }
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            Section("Level") {
                LevelMeterView(meter: player.meter, active: player.isPlaying)
                    .padding(.vertical, 4)
            }
            Section("Tempo") {
                Slider(value: $player.tempoScale, in: 0.5 ... 2.0, step: 0.05) { editing in
                    if !editing { logEvent("tempo", ["scale": String(format: "%.2f", player.tempoScale)]) }
                }
                Text(String(format: "%.2f×", player.tempoScale)).font(.footnote.monospacedDigit())
            }
            Section {
                NavigationLink("Acknowledgements") { AcknowledgementsView() }
            }
        }
        .navigationTitle("Player")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showPlaylist = true } label: { Label("Playlist", systemImage: "music.note.list") }
                    .accessibilityIdentifier("player.playlist")
            }
        }
        .sheet(isPresented: $showPlaylist) {
            NavigationStack {
                PlaylistScreen(store: store, currentID: entryID) { entry in
                    showPlaylist = false
                    switchTo(PlayerRoute(entry: entry), reason: "playlist")
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Done") { showPlaylist = false } }
                }
            }
        }
        .task(id: current) { await load() }
        .onAppear {
            // Cleared in onDisappear (the closure holds the view, which holds the player).
            player.onFinished = {
                logEvent("finished", [:])
                if let next { switchTo(next, reason: "auto-next") }
            }
        }
        .onDisappear {
            if player.isPlaying { logEvent("stop", ["why": "left player"]) }
            player.onFinished = nil
            player.stop()
        }
    }

    private var transport: some View {
        HStack {
            Button { previousTapped() } label: {
                Label("Previous", systemImage: "backward.end.fill").labelStyle(.iconOnly).font(.title2)
            }
            .disabled(!ready)
            .accessibilityIdentifier("player.previous")
            Spacer()
            Button { togglePlay() } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 56))
                    .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            }
            .disabled(!ready)
            .accessibilityIdentifier("player.playPause")
            Spacer()
            Button { if let next { switchTo(next, reason: "next") } } label: {
                Label("Next", systemImage: "forward.end.fill").labelStyle(.iconOnly).font(.title2)
            }
            .disabled(!ready || next == nil)
            .accessibilityIdentifier("player.next")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 24)
        .padding(.vertical, 4)
    }

    // MARK: Actions

    private func togglePlay() {
        if player.isPlaying {
            player.pause()
            logEvent("pause", [:])
        } else {
            player.play()
            logEvent(player.isPlaying ? "play" : "play_failed", [:])
        }
    }

    /// Restarts the track if more than 3 s in (or at the top of the list), else goes to the previous entry.
    private func previousTapped() {
        if player.position.seconds > 3 || previous == nil {
            player.seek(to: 0)
            logEvent("restart", [:])
        } else if let previous {
            switchTo(previous, reason: "previous")
        }
    }

    private func switchTo(_ route: PlayerRoute, reason: String) {
        var r = route
        r.autoplay = true
        logEvent("track_change", ["reason": reason, "to": r.title])
        if r.item == current.item {
            player.seek(to: 0)
            player.play()
        } else {
            current = r
        }
    }

    private func load() async {
        ready = false
        scrub = nil
        let route = current
        do {
            let sf = try await BundledSoundFont.load()
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
            status = "\(sf.info["INAM"] ?? "SoundFont") · \(midi.count) B SMF · \(player.song?.tracks.count ?? 0) track(s)"
            logEvent("load", ["bytes": "\(midi.count)", "duration": String(format: "%.2f", player.duration)])
            if route.autoplay {
                player.play()
                logEvent(player.isPlaying ? "play" : "play_failed", ["auto": "1"])
            }
        } catch {
            status = "Player unavailable: \(error)"
            DiagnosticsLog.shared.record(error: error, category: .playback, context: "PlayerView load \(route.title)")
        }
    }

    private func logEvent(_ kind: String, _ extra: [String: String]) {
        var p = extra
        p["kind"] = kind
        p["track"] = entryID ?? "adhoc"
        p["position"] = String(format: "%.2f", player.position.seconds)
        let details = extra.sorted { $0.key < $1.key }.map { kv in "\(kv.key)=\(kv.value)" }.joined(separator: " ")
        let message = details.isEmpty ? "player \(kind): \(title)" : "player \(kind): \(title) \(details)"
        DiagnosticsLog.shared.record(.info, .playback, message, payload: p)
    }

    static func clock(_ s: Double) -> String {
        let t = max(0, Int(s.rounded(.down)))
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}
