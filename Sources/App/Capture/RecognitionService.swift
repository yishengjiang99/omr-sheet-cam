import Foundation
import OMRHomrIOS

enum RecognitionOutcome: Equatable, Sendable {
    /// Full-page recognition not available yet (OMR Core is porting staff detection).
    case comingSoon
    /// SMF bytes ready for the Player.
    case midi(Data)
    case failed(String)
}

/// Page photo (upright JPEG bytes) → MIDI. Implementations run heavy work off the main thread.
protocol RecognitionService: Sendable {
    func recognize(imageData: Data) async -> RecognitionOutcome
}

/// Current app behavior: no recognition yet.
struct StubRecognitionService: RecognitionService {
    func recognize(imageData: Data) async -> RecognitionOutcome { .comingSoon }
}

/// Full-page path for when `parseSheetMusicWithLayout` accepts a page (`staffOnly: false`).
struct PageRecognitionService: RecognitionService {
    func recognize(imageData: Data) async -> RecognitionOutcome {
        await Task.detached(priority: .userInitiated) { () -> RecognitionOutcome in
            do {
                let result = try OMRHomrIOS.parseSheetMusicWithLayout(
                    input: ParseSheetMusicInput(imageData: imageData, staffOnly: false)
                )
                return result.midi.isEmpty ? .failed("no notes recognized") : .midi(result.midi)
            } catch {
                return .failed(String(describing: error))
            }
        }.value
    }
}

enum AppServices {
    /// Swap to `PageRecognitionService()` once OMR Core's full-page parse lands.
    static let recognition: any RecognitionService = StubRecognitionService()
}
