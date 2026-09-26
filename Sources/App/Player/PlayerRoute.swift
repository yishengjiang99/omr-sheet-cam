import Foundation
import OMRHomrIOS
import SwiftUI

/// Navigation destination for the Player (SMF bytes).
struct PlayerRoute: Hashable {
    let midi: Data
    var title: String = "Player"
}

enum PlayerDestination {
    /// Single swap point: replace the placeholder with the SF2 `PlayerView(midi:)` when it lands.
    @MainActor @ViewBuilder
    static func view(for route: PlayerRoute) -> some View {
        PlayerPlaceholderView(route: route)
    }
}

/// Stand-in until `Packages/SF2Player`'s `PlayerView` lands: plays via the smoke `SimpleMIDIPlayer`.
struct PlayerPlaceholderView: View {
    let route: PlayerRoute
    @State private var player = SimpleMIDIPlayer()
    @State private var error: String?

    var body: some View {
        List {
            Section {
                Text("SF2 player coming soon (placeholder playback).")
                    .foregroundStyle(.secondary)
                Text("\(route.midi.count) bytes SMF")
                    .font(.footnote.monospaced())
            }
            Section {
                Button("Play") {
                    do { try player.play(midiData: route.midi); error = nil } catch { self.error = "\(error)" }
                }
                Button("Stop") { player.stop() }
                Text(player.statusText).font(.footnote.monospaced()).foregroundStyle(.secondary)
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            }
        }
        .navigationTitle(route.title)
        .onDisappear { player.stop() }
    }
}

/// Bundled sample: the Gate-1 C-major scale (`gate1/expected.tokens.json`) written by the package's `SMFWriter`.
enum SampleMIDI {
    static func cMajorScale(bundle: Bundle = .main) throws -> Data {
        let json = try Gate1Runner.bundledFixturesDir(bundle).appendingPathComponent("expected.tokens.json")
        return SMFWriter().write(symbols: try Gate1Oracle.loadExpectedSymbols(from: json))
    }
}
