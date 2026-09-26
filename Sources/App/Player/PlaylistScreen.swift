import SwiftUI

/// Playlist: bundled samples (always there) then saved scans in the order they were added (the
/// Player's prev/next order). Tap to play; swipe to delete scans (samples can't be deleted).
struct PlaylistScreen: View {
    @ObservedObject var store: PlaylistStore
    /// Entry currently loaded in the Player, if any (shows a speaker badge).
    var currentID: String?
    var onSelect: (PlaylistEntry) -> Void

    @State private var deleteError: String?

    var body: some View {
        List {
            Section {
                ForEach(store.samples) { row($0) }
            } header: {
                Text("Samples")
            }
            Section {
                if store.scans.isEmpty {
                    Text("No scans yet. Every successful scan is saved here automatically.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(store.scans) { row($0) }
                    .onDelete(perform: delete)
            } header: {
                Text("Your scans")
            } footer: {
                if let deleteError { Text(deleteError).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Playlist")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("playlist.list")
    }

    private func row(_ e: PlaylistEntry) -> some View {
        Button { onSelect(e) } label: {
            HStack(spacing: 12) {
                Image(systemName: e.id == currentID ? "speaker.wave.2.fill" : (e.source == .sample ? "music.note" : "doc.viewfinder"))
                    .foregroundStyle(e.id == currentID ? Color.accentColor : Color.secondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.title).foregroundStyle(.primary).lineLimit(2)
                    if e.source == .scan {
                        Text(e.date, format: .dateTime.month().day().hour().minute())
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(PlayerView.clock(e.duration)).font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("playlist.row.\(e.id)")
        .deleteDisabled(!e.isDeletable)
    }

    private func delete(_ offsets: IndexSet) {
        let doomed = offsets.map { store.scans[$0] }
        do {
            for e in doomed { try store.delete(e) }
            deleteError = nil
        } catch {
            deleteError = "Delete failed: \(error)"
            DiagnosticsLog.shared.record(error: error, category: .playback, context: "playlist delete")
        }
    }
}
