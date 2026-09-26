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

/// SF2 player for SMF bytes (pushed from Result via `PlayerRoute`, or "Play sample").
struct PlayerView: View {
    let midi: Data
    var title: String = "Player"

    @StateObject private var player = SF2MIDIPlayer()
    @State private var status = "Loading SoundFont…"
    @State private var ready = false
    @State private var scrub: Double?

    var body: some View {
        List {
            Section {
                Text(status).font(.footnote).foregroundStyle(ready ? Color.secondary : Color.orange)
            }
            Section("Playback") {
                HStack(spacing: 32) {
                    Button {
                        player.isPlaying ? player.pause() : player.play()
                    } label: {
                        Label(player.isPlaying ? "Pause" : "Play", systemImage: player.isPlaying ? "pause.fill" : "play.fill")
                    }
                    Button { player.stop() } label: { Label("Stop", systemImage: "stop.fill") }
                }
                .buttonStyle(.borderless)
                .disabled(!ready)

                Slider(value: Binding(get: { scrub ?? player.position.seconds }, set: { scrub = $0 }),
                       in: 0 ... max(player.duration, 0.01)) { editing in
                    if !editing, let s = scrub { player.seek(to: s); scrub = nil }
                }
                .disabled(!ready)
                Text("\(Self.clock(scrub ?? player.position.seconds)) / \(Self.clock(player.duration))   tick \(Int(player.position.tick))")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Section("Tempo") {
                Slider(value: $player.tempoScale, in: 0.5 ... 2.0, step: 0.05)
                Text(String(format: "%.2f×", player.tempoScale)).font(.footnote.monospacedDigit())
            }
            Section {
                NavigationLink("Acknowledgements") { AcknowledgementsView() }
            }
        }
        .navigationTitle(title)
        .task { await load() }
        .onDisappear { player.stop() }
    }

    private func load() async {
        guard !ready else { return }
        do {
            let sf = try await BundledSoundFont.load()
            try player.load(soundFont: sf)
            try player.load(midi: midi)
            ready = true
            status = "\(sf.info["INAM"] ?? "SoundFont") · \(midi.count) B SMF · \(player.song?.tracks.count ?? 0) tracks"
        } catch {
            status = "Player unavailable: \(error)"
        }
    }

    static func clock(_ s: Double) -> String {
        let t = max(0, Int(s.rounded(.down)))
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}
