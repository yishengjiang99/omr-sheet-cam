import Foundation
import OMRScanKit

enum AppServices {
    /// Full-page homr recognition on the warmed ORT sessions (`Inference/PageRecognitionService.swift`).
    /// Always on: camera capture and photo-library import both run OMR (no developer gate).
    static let recognition: any RecognitionService = PageRecognitionService.shared

    /// Legacy UserDefaults key for the removed "Experimental page recognition" toggle.
    /// Cleared on launch so a persisted `false` cannot leave recognition looking broken.
    static let legacyExperimentalRecognitionKey = "developer.experimentalPageRecognition"

    static func clearLegacyRecognitionGate(_ defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: legacyExperimentalRecognitionKey)
    }
}
