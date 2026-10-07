import PhotosUI
import SF2Player
import SwiftUI

/// Library / playlist — app home: how-it-works art, Camera + Photos to start a scan, then
/// "Your scans" / "Samples". Tap a row to play. Mini-player at the bottom while something is loaded.
struct LibraryScreen: View {
    @ObservedObject private var store: PlaylistStore
    @EnvironmentObject private var controller: PlaybackController
    var showsMiniPlayer = true
    var onSelect: (PlaylistEntry) -> Void
    var onOpenPlayer: (() -> Void)?
    /// Empty-library / home "Try sample picture" (nil hides it, e.g. the Player's library sheet).
    var onTrySample: (() -> Void)?
    var onSettings: (() -> Void)?
    var onCamera: (() -> Void)?
    /// Photo-library import → same recognition path as camera (nil hides Photos on home).
    var onPhoto: ((CapturedPhoto) -> Void)?

    @State private var query = ""
    @State private var deleteError: String?
    @State private var renaming: PlaylistEntry?
    @State private var renameText = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var loadingPick = false
    @State private var importError: String?

    @MainActor
    init(
        showsMiniPlayer: Bool = true,
        onSettings: (() -> Void)? = nil,
        onCamera: (() -> Void)? = nil,
        onPhoto: ((CapturedPhoto) -> Void)? = nil,
        onOpenPlayer: (() -> Void)? = nil,
        onTrySample: (() -> Void)? = nil,
        onSelect: @escaping (PlaylistEntry) -> Void
    ) {
        _store = ObservedObject(wrappedValue: PlaylistStore.shared)
        self.showsMiniPlayer = showsMiniPlayer
        self.onSettings = onSettings
        self.onCamera = onCamera
        self.onPhoto = onPhoto
        self.onOpenPlayer = onOpenPlayer
        self.onTrySample = onTrySample
        self.onSelect = onSelect
    }

    private var results: [PlaylistEntry] { store.search(query) }
    private var scans: [PlaylistEntry] { results.filter { $0.source == .scan } }
    private var samples: [PlaylistEntry] { results.filter { $0.source == .sample } }
    private var isHomeChrome: Bool { onCamera != nil || onPhoto != nil || onSettings != nil }

    var body: some View {
        List {
            if isHomeChrome, query.isEmpty {
                Section {
                    HowItWorksArt()
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                    scanActions
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 12, trailing: 16))
                        .listRowBackground(Color.clear)
                    if let importError {
                        Text(importError).font(.footnote).foregroundStyle(.red)
                    }
                }
            }
            Section {
                if scans.isEmpty {
                    Text(query.isEmpty ? "No scans yet. Take a photo or import one — it shows up here." : "No scans match “\(query)”.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if query.isEmpty, let onTrySample {
                        Button(action: onTrySample) {
                            Label(SamplePicture.buttonTitle, systemImage: "music.note")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(Theme.coral)
                        .accessibilityIdentifier("library.trySample")
                    }
                }
                ForEach(scans) { e in
                    row(e)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) { delete([e]) } label: { Label("Delete", systemImage: "trash") }
                            Button { beginRename(e) } label: { Label("Rename", systemImage: "pencil") }
                                .tint(.indigo)
                        }
                        .contextMenu { editMenu(e) }
                }
            } header: {
                header("Your scans", count: store.scans.count)
            } footer: {
                if let deleteError { Text(deleteError).foregroundStyle(.red) }
            }
            Section {
                ForEach(samples) { e in
                    row(e).contextMenu { editMenu(e) }
                }
            } header: {
                header("Samples", count: store.samples.count)
            }
        }
        .listStyle(.plain)
        .searchable(text: $query, prompt: "Search your music")
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if let onSettings {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onSettings) {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                    .accessibilityIdentifier("library.settings")
                }
            }
            if onCamera != nil || onPhoto != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        if onPhoto != nil {
                            PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                                Image(systemName: "photo.on.rectangle")
                            }
                            .disabled(loadingPick)
                            .accessibilityLabel("Import photo")
                            .accessibilityIdentifier("library.photos")
                        }
                        if let onCamera {
                            Button(action: onCamera) {
                                Image(systemName: "camera.fill")
                            }
                            .accessibilityLabel("Camera")
                            .accessibilityIdentifier("library.camera")
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if showsMiniPlayer && controller.current != nil {
                MiniPlayer(controller: controller) { onOpenPlayer?() }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }
        }
        .accessibilityIdentifier("library.list")
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Title", text: $renameText)
                .accessibilityIdentifier("library.renameField")
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Save") { commitRename() }
        }
        .onChange(of: pickerItem) { _, item in
            if let item { loadPicked(item) }
        }
    }

    private var scanActions: some View {
        HStack(spacing: 12) {
            if let onCamera {
                Button(action: onCamera) {
                    Label("Camera", systemImage: "camera.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(CoralButtonStyle())
                .accessibilityIdentifier("library.cameraCTA")
            }
            if onPhoto != nil {
                PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                    Label(loadingPick ? "Loading…" : "Photos", systemImage: "photo.on.rectangle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(Theme.coral)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Theme.coral, lineWidth: 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color(.systemBackground))
                                )
                        )
                }
                .disabled(loadingPick)
                .accessibilityIdentifier("library.photosCTA")
            }
        }
    }

    private func loadPicked(_ item: PhotosPickerItem) {
        loadingPick = true
        importError = nil
        Task {
            defer { loadingPick = false; pickerItem = nil }
            do {
                let image = try await PhotoLibraryImport.uprightImage(from: item)
                onPhoto?(CapturedPhoto(image: image, source: .library))
            } catch {
                importError = error.localizedDescription
                DiagnosticsLog.shared.record(error: error, category: .capture, context: "Library Photos pick")
            }
        }
    }

    @ViewBuilder
    private func editMenu(_ e: PlaylistEntry) -> some View {
        Button { onSelect(e) } label: { Label("Play", systemImage: "play.fill") }
        if let export = store.export(for: e) {
            ShareLink(item: export, preview: SharePreview(e.title)) {
                Label("Share MIDI", systemImage: "square.and.arrow.up")
            }
            .accessibilityIdentifier("library.share.\(e.id)")
        }
        if e.isDeletable {
            Button { beginRename(e) } label: { Label("Rename", systemImage: "pencil") }
            Button(role: .destructive) { delete([e]) } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func beginRename(_ e: PlaylistEntry) {
        renameText = e.title
        renaming = e
    }

    /// Updates the title in index.json; the .mid file keeps its name.
    private func commitRename() {
        guard let e = renaming else { return }
        renaming = nil
        do {
            try store.rename(e, to: renameText)
            deleteError = nil
        } catch {
            deleteError = "Rename failed: \(error)"
            DiagnosticsLog.shared.record(error: error, category: .playback, context: "library rename")
        }
    }

    private func header(_ title: String, count: Int) -> some View {
        HStack {
            Text(title).font(.title3.weight(.bold)).foregroundStyle(.primary).textCase(nil)
            Spacer()
            Text("\(count)").font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func row(_ e: PlaylistEntry) -> some View {
        let playing = e.id == controller.entryID
        return Button { onSelect(e) } label: {
            HStack(spacing: 12) {
                ArtworkView(image: PlaybackController.artwork(for: e), cornerRadius: 8, glyphSize: 18)
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(e.title).foregroundStyle(playing ? Theme.coral : Color.primary).lineLimit(1)
                        if Self.isNew(e) {
                            Text("NEW").font(.caption2.weight(.bold)).foregroundStyle(Theme.coral)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Theme.coralSoft, in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    Text(Self.detail(e)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if playing {
                    Image(systemName: "waveform").foregroundStyle(Theme.coral).symbolEffect(.variableColor.iterative, isActive: controller.player.isPlaying)
                        .accessibilityLabel("Now playing")
                } else {
                    Menu {
                        editMenu(e)
                    } label: {
                        Image(systemName: "ellipsis").foregroundStyle(.secondary).frame(width: 32, height: 32)
                    }
                    .accessibilityLabel("More for \(e.title)")
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("library.row.\(e.id)")
    }

    static func isNew(_ e: PlaylistEntry, now: Date = Date()) -> Bool {
        e.source == .scan && now.timeIntervalSince(e.date) < 24 * 3600
    }

    static func detail(_ e: PlaylistEntry) -> String {
        let length = PlayerView.clock(e.duration)
        guard e.source == .scan else { return length }
        let day = Calendar.current.isDateInToday(e.date) ? "Today" : e.date.formatted(.dateTime.month(.abbreviated).day())
        return "\(day) · \(length)"
    }

    private func delete(_ entries: [PlaylistEntry]) {
        do {
            for e in entries { try store.delete(e) }
            deleteError = nil
        } catch {
            deleteError = "Delete failed: \(error)"
            DiagnosticsLog.shared.record(error: error, category: .playback, context: "library delete")
        }
    }
}

/// Onboarding explain art: photo → sheet music → play (no camera on first launch).
struct HowItWorksArt: View {
    var body: some View {
        VStack(spacing: 14) {
            Text("Photo → music → play")
                .font(.title3.weight(.bold))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Snap or import a page of sheet music. This app reads the notes on your iPhone and plays them back.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 0) {
                step(icon: "camera.fill", title: "Photo")
                chevron
                step(icon: "music.note.list", title: "Read")
                chevron
                step(icon: "play.fill", title: "Play")
            }
            .padding(.vertical, 8)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.coralSoft.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.coral.opacity(0.25), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("library.howItWorks")
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.bold))
            .foregroundStyle(.secondary)
            .frame(width: 28)
    }

    private func step(icon: String, title: String) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(Theme.coral.opacity(0.15)).frame(width: 52, height: 52)
                Image(systemName: icon).font(.title3.weight(.semibold)).foregroundStyle(Theme.coral)
            }
            Text(title).font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
    }
}


/// Bottom mini-player (Library): artwork, title, instrument · tempo, play/pause, next, progress.
struct MiniPlayer: View {
    @ObservedObject var controller: PlaybackController
    @ObservedObject private var player: SF2MIDIPlayer
    var onOpen: () -> Void

    init(controller: PlaybackController, onOpen: @escaping () -> Void) {
        _controller = ObservedObject(wrappedValue: controller)
        _player = ObservedObject(wrappedValue: controller.player)
        self.onOpen = onOpen
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                Button(action: onOpen) {
                    HStack(spacing: 12) {
                        ArtworkView(image: controller.artwork, cornerRadius: 10, glyphSize: 18).frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(controller.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text("\(controller.settings.instrument.name) · \(AppSettings.tempoLabel(controller.settings.tempo))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("miniplayer.open")
                Button { controller.togglePlay() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title3)
                        .frame(width: 40, height: 40)
                }
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                .accessibilityIdentifier("miniplayer.playPause")
                Button { controller.next() } label: {
                    Image(systemName: "forward.fill").font(.title3).frame(width: 40, height: 40)
                }
                .disabled(controller.nextRoute == nil)
                .accessibilityLabel("Next")
            }
            .foregroundStyle(Color.primary)
            GeometryReader { geo in
                Capsule().fill(Color.primary.opacity(0.1))
                    .overlay(alignment: .leading) {
                        Capsule().fill(Theme.coral)
                            .frame(width: geo.size.width * CGFloat(player.duration > 0 ? min(1, player.position.seconds / player.duration) : 0))
                    }
            }
            .frame(height: 3)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }
}
