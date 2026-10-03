#if DEBUG
import OMRHomrIOS
import SwiftUI
import UIKit

/// Debug-only launch hook for the ios-screenshots workflow:
/// `simctl launch <sim> com.ragnus.vp -OMRScreenshot result|player|library|settings`.
/// "result" shows the bundled Gate-1 staff as a recognized scan (oracle tokens → SMFWriter MIDI).
enum ScreenshotDemo {
    static var route: String? { UserDefaults.standard.string(forKey: "OMRScreenshot") }

    @MainActor
    static func initialPath() -> [RootFlowView.Route] {
        switch route {
        case "library", "playlist":
            seedLibrary()
            return [.library]
        case "player": return [.player(.sample(SampleMIDI.odeToJoyKey, title: "Ode to Joy (sample)"))]
        case "result":
            guard let photo = try? gate1Photo() else { return [] }
            return [.result(photo)]
        default: return []
        }
    }

    /// Two demo scans (Gate-1 oracle MIDI and the C-scale sample MIDI, titled as demos) so the
    /// Library screenshot shows scans above the samples, and the first loaded in the mini-player.
    @MainActor
    static func seedLibrary() {
        let store = PlaylistStore.shared
        if !store.scans.contains(where: { $0.title.hasPrefix("Demo scan") }) {
            let now = Date()
            if let dir = try? Gate1Runner.bundledFixturesDir(),
               let symbols = try? Gate1Oracle.loadExpectedSymbols(from: dir.appendingPathComponent("expected.tokens.json")) {
                _ = try? store.addScan(midi: SMFWriter().write(symbols: symbols), title: "Demo scan: Gate-1 staff", date: now.addingTimeInterval(-3 * 86400))
            }
            if let e = store.entry(id: "sample:c-major-scale"), let midi = try? store.midiData(for: e) {
                _ = try? store.addScan(midi: midi, title: "Demo scan: warm-up scale", date: now.addingTimeInterval(-600))
            }
        }
        if let first = store.entries.first(where: { $0.source == .scan }) {
            var r = PlayerRoute(entry: first)
            r.autoplay = false
            PlaybackController.shared.open(r, reason: "screenshot")
        }
    }

    static func gate1Photo() throws -> CapturedPhoto {
        let dir = try Gate1Runner.bundledFixturesDir()
        guard let img = UIImage(contentsOfFile: dir.appendingPathComponent("staff.png").path) else {
            throw Gate1Runner.RunnerError.fixturesMissing("staff.png unreadable")
        }
        return CapturedPhoto(image: img, source: .library)
    }

    /// Recognition stand-in: the Gate-1 oracle tokens as a recognized result.
    struct Recognition: RecognitionService {
        func recognize(imageData: Data) async -> RecognitionOutcome {
            do {
                let dir = try Gate1Runner.bundledFixturesDir()
                let symbols = try Gate1Oracle.loadExpectedSymbols(from: dir.appendingPathComponent("expected.tokens.json"))
                let notes = RecognizedNote.fromSymbols(symbols)
                return .recognized(RecognitionDetails(
                    midi: SMFWriter().write(symbols: symbols), notes: notes, staffCount: 1,
                    warnings: [], layoutSource: LayoutSource.midiFallback.rawValue, ms: 0
                ))
            } catch {
                return .failed("\(error)")
            }
        }
    }
}
#endif
