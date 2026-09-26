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
        case "library", "playlist": return [.library]
        case "player": return [.player(.sample("sweden", title: "Sweden (sample)"))]
        case "result":
            guard let photo = try? gate1Photo() else { return [] }
            return [.result(photo)]
        default: return []
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
