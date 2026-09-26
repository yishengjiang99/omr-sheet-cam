import Foundation
import OMRHomrIOS
import SwiftUI

/// Navigation destination for the Player: a playlist entry (prev/next work) or ad-hoc SMF bytes.
struct PlayerRoute: Hashable {
    enum Item: Hashable {
        /// `PlaylistEntry.id`.
        case playlist(String)
        case midi(Data)
    }

    var item: Item
    var title: String = "Player"
    /// Start playing as soon as the SoundFont + MIDI are loaded.
    var autoplay = true

    init(midi: Data, title: String = "Player", autoplay: Bool = true) {
        item = .midi(midi); self.title = title; self.autoplay = autoplay
    }

    init(entry: PlaylistEntry, autoplay: Bool = true) {
        item = .playlist(entry.id); title = entry.title; self.autoplay = autoplay
    }

    /// Bundled sample by key (`PlaylistSample.key`, e.g. "sweden").
    static func sample(_ key: String, title: String, autoplay: Bool = true) -> PlayerRoute {
        var r = PlayerRoute(midi: Data(), title: title, autoplay: autoplay)
        r.item = .playlist("sample:\(key)")
        return r
    }
}

enum PlayerDestination {
    @MainActor @ViewBuilder
    static func view(for route: PlayerRoute) -> some View {
        PlayerView(route: route)
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
