import Foundation
import OMRHomrIOS
import SwiftUI

/// Navigation destination for the Player (SMF bytes).
struct PlayerRoute: Hashable {
    let midi: Data
    var title: String = "Player"
}

enum PlayerDestination {
    @MainActor @ViewBuilder
    static func view(for route: PlayerRoute) -> some View {
        PlayerView(midi: route.midi, title: route.title)
    }
}

/// Bundled samples: gbk `sweden.midi`, and the Gate-1 C-major scale (`gate1/expected.tokens.json`) written by `SMFWriter`.
enum SampleMIDI {
    enum SampleError: Error { case missing(String) }

    /// gbk's `sweden.midi` (fixtures/sf2/sweden.midi), bundled at the app root for "Play sample".
    static func sweden(bundle: Bundle = .main) throws -> Data {
        guard let url = bundle.url(forResource: "sweden", withExtension: "midi") else { throw SampleError.missing("sweden.midi") }
        return try Data(contentsOf: url)
    }

    static func cMajorScale(bundle: Bundle = .main) throws -> Data {
        let json = try Gate1Runner.bundledFixturesDir(bundle).appendingPathComponent("expected.tokens.json")
        return SMFWriter().write(symbols: try Gate1Oracle.loadExpectedSymbols(from: json))
    }
}
