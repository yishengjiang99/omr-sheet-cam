import Foundation
import OMRHomrIOS

enum RecognitionOutcome: Equatable, Sendable {
    /// Full-page recognition not available yet (OMR Core is porting staff detection).
    case comingSoon
    /// SMF bytes for the Player plus noteLayout / staffCount / warnings for the compare overlay.
    case recognized(RecognitionDetails)
    case failed(String)

    var name: String {
        switch self {
        case .comingSoon: return "comingSoon"
        case .recognized: return "recognized"
        case .failed: return "failed"
        }
    }
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
                let t0 = DispatchTime.now()
                let result = try OMRHomrIOS.parseSheetMusicWithLayout(
                    input: ParseSheetMusicInput(imageData: imageData, staffOnly: false)
                )
                let ms = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000
                return result.midi.isEmpty ? .failed("no notes recognized") : .recognized(RecognitionDetails(result, ms: ms))
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
