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

/// Page recognition gate. ON: the real `PageRecognitionService` runs on every capture.
/// Developers can still override it in Settings → Developer →
/// "Experimental page recognition" (UserDefaults `key`).
enum RecognitionGate {
    /// THE switch: `true` = page recognition on for everyone. Turned on 2026-09-27:
    /// SegNet on the CoreML EP is fixed in OMRHomrIOS and green on ios-sim (12/12 Gate-1).
    static let defaultEnabled = true

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
