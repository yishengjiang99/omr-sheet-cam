import Foundation
import OMRHomrIOS

enum RecognitionOutcome: Equatable, Sendable {
    /// No recognizer (`StubRecognitionService`, previews / tests only).
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

/// Page photo (encoded JPEG / HEIC / PNG bytes; EXIF orientation honored) → MIDI. Implementations run heavy work off the main thread.
protocol RecognitionService: Sendable {
    func recognize(imageData: Data) async -> RecognitionOutcome
}

/// Placeholder recognizer (previews / tests); the app uses `PageRecognitionService`.
struct StubRecognitionService: RecognitionService {
    func recognize(imageData: Data) async -> RecognitionOutcome { .comingSoon }
}

enum AppServices {
    /// Full-page homr recognition on the warmed ORT sessions (`Inference/PageRecognitionService.swift`).
    static let recognition: any RecognitionService = PageRecognitionService.shared
}
