import SF2Player
import SwiftUI

/// Library (redesign 05-library): search, "Your scans" (newest first, swipe or ⋯ to delete) and
/// "Samples" (always there, not deletable). Tap a row to play it. A mini-player sits at the
/// bottom while something is loaded.
struct LibraryScreen: View {
    @ObservedObject private var store: PlaylistStore
    @ObservedObject private var controller: PlaybackController
    var showsMiniPlayer = true
    var onSelect: (PlaylistEntry) -> Void
    var onOpenPlayer: (() -> Void)?

    @State private var query = ""
    @State private var deleteError: String?

    @MainActor
    init(showsMiniPlayer: Bool = true, onOpenPlayer: (() -> Void)? = nil, onSelect: @escaping (PlaylistEntry) -> Void) {
        _store = ObservedObject(wrappedValue: PlaylistStore.shared)
        _controller = ObservedObject(wrappedValue: PlaybackController.shared)
        self.showsMiniPlayer = showsMiniPlayer
        self.onOpenPlayer = onOpenPlayer
        self.onSelect = onSelect
    }

    private var results: [PlaylistEntry] { store.search(query) }
    private var scans: [PlaylistEntry] { results.filter { $0.source == .scan } }
    private var samples: [PlaylistEntry] { results.filter { $0.source == .sample } }

    var body: some View {
        List {
            Section {
                if scans.isEmpty {
                    Text(query.isEmpty ? "No scans yet. Scan a page and it shows up here." : "No scans match “\(query)”.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(scans) { row($0) }
                    .onDelete { offsets in delete(offsets.map { scans[$0] }) }
            } header: {
                header("Your scans", count: store.scans.count)
            } footer: {
                if let deleteError { Text(deleteError).foregroundStyle(.red) }
            }
            Section {
                ForEach(samples) { row($0) }
            } header: {
                header("Samples", count: store.samples.count)
            }
        }
        .listStyle(.plain)
        .searchable(text: $query, prompt: "Search your music")
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.large)
        .safeAreaInset(edge: .bottom) {
            if showsMiniPlayer && controller.current != nil {
                MiniPlayer(controller: controller) { onOpenPlayer?() }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }
        }
        .accessibilityIdentifier("library.list")
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
                } else if e.isDeletable {
                    Menu {
                        Button { onSelect(e) } label: { Label("Play", systemImage: "play.fill") }
                        Button(role: .destructive) { delete([e]) } label: { Label("Delete", systemImage: "trash") }
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
        .deleteDisabled(!e.isDeletable)
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
