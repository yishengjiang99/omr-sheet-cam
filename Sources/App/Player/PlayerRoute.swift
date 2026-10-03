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
    /// Auto-advance to the next Library item when this one finishes.
    /// True only when playback starts from the Library (playlist mode);
    /// a just-scanned sheet plays once and stops.
    var advanceOnFinish = false

    init(midi: Data, title: String = "Player", autoplay: Bool = true) {
        item = .midi(midi); self.title = title; self.autoplay = autoplay
    }

    init(entry: PlaylistEntry, autoplay: Bool = true) {
        item = .playlist(entry.id); title = entry.title; self.autoplay = autoplay
    }

    /// Bundled sample by key (`PlaylistSample.key`, e.g. "ode-to-joy").
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

/// Bundled samples: public-domain Ode to Joy (`fixtures/samples/ode-to-joy.mid`), and the Gate-1
/// C-major scale (`gate1/expected.tokens.json`) written by `SMFWriter`.
enum SampleMIDI {
    enum SampleError: Error { case missing(String) }

    /// Library key of the "Play a sample" song.
    static let odeToJoyKey = "ode-to-joy"

    /// Beethoven's Ode to Joy (public domain): right-hand melody of `fixtures/samples/ode-to-joy.ly`
    /// (the "Try sample picture" page) + a simple left hand; written by
    /// `scripts/samples/make-ode-to-joy-midi.py`, bundled at the app root.
    static func odeToJoy(bundle: Bundle = .main) throws -> Data {
        guard let url = bundle.url(forResource: "ode-to-joy", withExtension: "mid") else { throw SampleError.missing("ode-to-joy.mid") }
        return try Data(contentsOf: url)
    }

    static func cMajorScale(bundle: Bundle = .main) throws -> Data {
        let json = try Gate1Runner.bundledFixturesDir(bundle).appendingPathComponent("expected.tokens.json")
        return SMFWriter().write(symbols: try Gate1Oracle.loadExpectedSymbols(from: json))
    }
}
