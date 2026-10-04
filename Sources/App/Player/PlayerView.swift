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
    /// Sheet (scan photo with the playing notes highlighted) vs. Cover artwork.
    @State private var showSheet = true
    @State private var followPlayback = false
    /// Sheet taps mark the A–B loop instead of seeking.
    @State private var tapSetsLoop = false

    private var sheetAvailable: Bool { controller.layout != nil && controller.sheetImage != nil }

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
                if sheetAvailable {
                    Picker("View", selection: $showSheet) {
                        Text("Sheet").tag(true)
                        Text("Cover").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 240)
                    .accessibilityIdentifier("player.viewMode")
                }
                if sheetAvailable, showSheet, let layout = controller.layout, let image = controller.sheetImage {
                    sheet(layout: layout, image: image)
                } else {
                    ArtworkView(image: controller.artwork, cornerRadius: 24, glyphSize: 72)
                        .aspectRatio(1, contentMode: .fit)
                        .frame(maxWidth: 340)
                        .shadow(color: Theme.coral.opacity(0.25), radius: 20, y: 10)
                        .accessibilityHidden(true)
                }
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
                if let export = controller.export {
                    ShareLink(item: export, preview: SharePreview(controller.title)) {
                        Label("Share MIDI", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("player.share")
                }
            }
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
                    r.advanceOnFinish = true // playlist mode: keep going at track end
                    controller.open(r, reason: "library")
                }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { showLibrary = false } } }
            }
            .environmentObject(controller)
        }
        .onAppear { controller.open(route) }
    }

    private func sheet(layout: ScanLayout, image: UIImage) -> some View {
        VStack(spacing: 6) {
            SheetFollowView(image: image, layout: layout, activeIDs: player.activeNoteIDs, follow: followPlayback,
                            tinted: controller.loopNoteSet, badges: controller.loopNoteIDs) { note in
                if tapSetsLoop {
                    controller.markLoopPoint(note: note)
                    if player.loop != nil { tapSetsLoop = false }
                } else {
                    controller.seek(toNote: note)
                }
            }
            .frame(height: 380)
            HStack {
                Toggle(isOn: $followPlayback) { Label("Follow", systemImage: "scope") }
                    .toggleStyle(.button)
                    .accessibilityIdentifier("player.sheet.follow")
                Toggle(isOn: $tapSetsLoop) { Label("Tap A–B", systemImage: "repeat") }
                    .toggleStyle(.button)
                    .accessibilityIdentifier("player.sheet.tapLoop")
                Spacer()
                Text(sheetHint).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            }
            .font(.caption.weight(.semibold))
        }
    }

    private var sheetHint: String {
        guard tapSetsLoop else { return "Tap a note to play from there" }
        return controller.pendingLoopStart == nil ? "Tap the first note of the loop" : "Tap the last note of the loop"
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
        VStack(spacing: 10) {
            HStack(spacing: 12) { tempoChip; instrumentChip }
            HStack(spacing: 12) {
                keyChip
                if player.noteTracks.count >= 2 { handsChip }
            }
            loopControl
        }
    }

    private var handsChip: some View {
        let tracks = player.noteTracks
        let names = PlaybackController.handNames(tracks)
        return Menu {
            Button { controller.solo(nil) } label: {
                Self.menuItem(tracks.count == 2 ? "Both hands" : "All parts", checked: player.mutedTracks.isEmpty)
            }
            ForEach(tracks) { t in
                Button { controller.solo(t.index) } label: {
                    Self.menuItem("\(names[t.index] ?? t.name) only",
                                  checked: player.mutedTracks == Set(tracks.map(\.index).filter { $0 != t.index }))
                }
            }
            Divider()
            ForEach(tracks) { t in
                Toggle("Mute \(names[t.index] ?? t.name)", isOn: Binding(
                    get: { player.mutedTracks.contains(t.index) }, set: { controller.setMuted(t.index, $0) }))
            }
        } label: {
            chip(icon: "hand.raised", text: PlaybackController.handsLabel(tracks, muted: player.mutedTracks))
        }
        .disabled(!controller.ready)
        .accessibilityLabel("Hands")
        .accessibilityValue(PlaybackController.handsLabel(tracks, muted: player.mutedTracks))
        .accessibilityIdentifier("player.hands")
    }

    /// A–B loop: "A" marks the current position, then "B" closes the loop; ✕ clears it.
    private var loopControl: some View {
        HStack(spacing: 10) {
            Image(systemName: "repeat").foregroundStyle(player.loop != nil ? Theme.coral : Color.secondary)
            if let loop = player.loop {
                Text("Loop \(Self.clock(loop.start))–\(Self.clock(loop.end))")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .accessibilityIdentifier("player.loop.range")
                Spacer()
                Button { controller.clearLoop() } label: { Label("Clear loop", systemImage: "xmark.circle.fill") }
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier("player.loop.clear")
            } else {
                Text(controller.pendingLoopStart.map { "A at \(Self.clock($0)) · set B" } ?? "Loop a passage")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Button(controller.pendingLoopStart == nil ? "Set A" : "Set B") {
                    controller.markLoopPoint(at: player.position.seconds)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("player.loop.mark")
                if controller.pendingLoopStart != nil {
                    Button { controller.clearLoop() } label: { Label("Cancel loop", systemImage: "xmark.circle.fill") }
                        .labelStyle(.iconOnly)
                }
            }
        }
        .foregroundStyle(Color.primary)
        .disabled(!controller.ready)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.background, in: Capsule())
        .overlay(Capsule().stroke(Color.primary.opacity(0.08)))
    }

    private var keyChip: some View {
        Menu {
            Picker("Transpose", selection: Binding(get: { player.transpose }, set: { controller.setTranspose($0) })) {
                ForEach(PlaybackController.transposeChoices.reversed(), id: \.self) { t in
                    Text(PlaybackController.transposeName(t)).tag(t)
                }
            }
        } label: {
            chip(icon: "arrow.up.arrow.down", text: PlaybackController.keyLabel(player.transpose))
        }
        .disabled(!controller.ready)
        .accessibilityLabel("Transpose")
        .accessibilityValue(PlaybackController.keyLabel(player.transpose))
        .accessibilityIdentifier("player.transpose")
    }

    private var tempoChip: some View {
        Menu {
            Picker("Tempo", selection: $settings.tempo) {
                ForEach(AppSettings.tempoChoices, id: \.self) { Text(AppSettings.tempoLabel($0)).tag($0) }
            }
        } label: {
            chip(icon: "metronome", text: AppSettings.tempoLabel(settings.tempo))
        }
        .accessibilityIdentifier("player.tempo")
    }

    private var instrumentChip: some View {
        Menu {
            Picker("Instrument", selection: $settings.instrument) {
                ForEach(Instrument.all) { Text($0.name).tag($0) }
            }
        } label: {
            chip(icon: "pianokeys", text: settings.instrument.name)
        }
        .accessibilityIdentifier("player.instrument")
    }

    @ViewBuilder
    private static func menuItem(_ title: String, checked: Bool) -> some View {
        if checked { Label(title, systemImage: "checkmark") } else { Text(title) }
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
