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

/// Page recognition gate. OFF: a capture shows "Recognition coming soon" (the page path is never
/// called). ON: the real `PageRecognitionService`. Developers override it in Settings → Developer →
/// "Experimental page recognition" (UserDefaults `key`); everyone else gets `defaultEnabled`.
enum RecognitionGate {
    /// THE switch: set to `true` to turn page recognition on for everyone (once SegNet on the CoreML
    /// EP is fixed in OMRHomrIOS and green on ios-sim).
    static let defaultEnabled = false

    static let key = "developer.experimentalPageRecognition"

    /// Developer override if set, else `defaultEnabled`.
    static func isEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key) as? Bool ?? defaultEnabled
    }
}

/// Returns `.comingSoon` while the gate is closed, else forwards to `real`.
struct GatedRecognitionService: RecognitionService {
    let real: any RecognitionService
    var isEnabled: @Sendable () -> Bool = { RecognitionGate.isEnabled() }

    func recognize(imageData: Data) async -> RecognitionOutcome {
        guard isEnabled() else { return .comingSoon }
        return await real.recognize(imageData: imageData)
    }
}

enum AppServices {
    /// Full-page homr recognition on the warmed ORT sessions (`Inference/PageRecognitionService.swift`),
    /// behind `RecognitionGate`.
    static let recognition: any RecognitionService = GatedRecognitionService(real: PageRecognitionService.shared)
}
