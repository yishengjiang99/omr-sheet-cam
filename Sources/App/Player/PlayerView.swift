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

/// Now Playing (redesign 04-player): artwork, title, live level meter, seek with times,
/// prev / play-pause / next, tempo and instrument chips. Drives the ONE app-wide
/// `PlaybackController` (injected by `OMRSheetCamApp` via `.environmentObject`), so playback
/// continues across navigation and shows in the mini-player on Scan and Library.
struct PlayerView: View {
    @EnvironmentObject private var controller: PlaybackController
    let route: PlayerRoute

    init(route: PlayerRoute) { self.route = route }

    init(midi: Data, title: String = "Player") {
        self.init(route: PlayerRoute(midi: midi, title: title, autoplay: false))
    }

    var body: some View { PlayerScreen(route: route, controller: controller) }

    static func clock(_ s: Double) -> String {
        let t = max(0, Int(s.rounded(.down)))
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}

struct PlayerScreen: View {
    @ObservedObject private var controller: PlaybackController
    @ObservedObject private var player: SF2MIDIPlayer
    @ObservedObject private var settings: AppSettings
    private let route: PlayerRoute
    @State private var scrub: Double?
    @State private var showLibrary = false

    init(route: PlayerRoute, controller: PlaybackController) {
        self.route = route
        _controller = ObservedObject(wrappedValue: controller)
        _player = ObservedObject(wrappedValue: controller.player)
        _settings = ObservedObject(wrappedValue: controller.settings)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text(controller.isFromLibrary ? "PLAYING FROM LIBRARY" : "NOW PLAYING")
                    .font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(.secondary)
                ArtworkView(image: controller.artwork, cornerRadius: 24, glyphSize: 72)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 340)
                    .shadow(color: Theme.coral.opacity(0.25), radius: 20, y: 10)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(controller.title).font(.title2.weight(.bold)).lineLimit(2)
                        .accessibilityIdentifier("player.title")
                    Text(controller.subtitle).font(.subheadline).foregroundStyle(.secondary)
                    if !controller.status.isEmpty {
                        Text(controller.status).font(.footnote).foregroundStyle(controller.ready ? Color.secondary : Theme.coral)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                LevelMeterView(meter: player.meter, active: player.isPlaying)
                seekBar
                transport
                chips
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(LinearGradient(colors: [Theme.coralSoft, Theme.cream], startPoint: .top, endPoint: .center).ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showLibrary = true } label: { Label("Library", systemImage: "music.note.list") }
                    .accessibilityIdentifier("player.library")
            }
        }
        .sheet(isPresented: $showLibrary) {
            NavigationStack {
                LibraryScreen(showsMiniPlayer: false) { entry in
                    showLibrary = false
                    var r = PlayerRoute(entry: entry)
                    r.autoplay = true
                    controller.open(r, reason: "library")
                }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { showLibrary = false } } }
            }
            .environmentObject(controller)
        }
        .onAppear { controller.open(route) }
    }

    private var seekBar: some View {
        VStack(spacing: 4) {
            Slider(value: Binding(get: { scrub ?? player.position.seconds }, set: { scrub = $0 }),
                   in: 0 ... max(player.duration, 0.01)) { editing in
                if !editing, let s = scrub {
                    controller.seek(to: s)
                    scrub = nil
                }
            }
            .tint(Color.primary)
            .disabled(!controller.ready)
            .accessibilityIdentifier("player.seek")
            HStack {
                Text(Self.clock(scrub ?? player.position.seconds)).accessibilityIdentifier("player.elapsed")
                Spacer()
                Text(Self.clock(player.duration)).accessibilityIdentifier("player.total")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private var transport: some View {
        HStack {
            Button { controller.previous() } label: {
                Image(systemName: "backward.fill").font(.title)
            }
            .accessibilityLabel("Previous")
            .accessibilityIdentifier("player.previous")
            Spacer()
            Button { controller.togglePlay() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 34, weight: .bold))
                    .frame(width: 88, height: 88)
            }
            .buttonStyle(CoralButtonStyle())
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            .accessibilityIdentifier("player.playPause")
            Spacer()
            Button { controller.next() } label: {
                Image(systemName: "forward.fill").font(.title)
            }
            .disabled(controller.nextRoute == nil)
            .accessibilityLabel("Next")
            .accessibilityIdentifier("player.next")
        }
        .foregroundStyle(Color.primary)
        .disabled(!controller.ready)
        .padding(.horizontal, 28)
    }

    private var chips: some View {
        HStack(spacing: 12) {
            Menu {
                Picker("Tempo", selection: $settings.tempo) {
                    ForEach(AppSettings.tempoChoices, id: \.self) { Text(AppSettings.tempoLabel($0)).tag($0) }
                }
            } label: {
                chip(icon: "metronome", text: AppSettings.tempoLabel(settings.tempo))
            }
            .accessibilityIdentifier("player.tempo")
            Menu {
                Picker("Instrument", selection: $settings.instrument) {
                    ForEach(Instrument.all) { Text($0.name).tag($0) }
                }
            } label: {
                chip(icon: "pianokeys", text: settings.instrument.name)
            }
            .accessibilityIdentifier("player.instrument")
        }
    }

    private func chip(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text)
            Image(systemName: "chevron.down").font(.caption2)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Color.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.background, in: Capsule())
        .overlay(Capsule().stroke(Color.primary.opacity(0.08)))
    }

    private static func clock(_ s: Double) -> String { PlayerView.clock(s) }
}
