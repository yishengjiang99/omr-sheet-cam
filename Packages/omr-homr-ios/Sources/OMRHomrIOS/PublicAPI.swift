import Foundation

/// Public entry for App / Player consumers.
///
/// Gate-1 status: returns a structured error until encoder+decoder ORT sessions
/// and C-scale oracle match are wired. App shell (when linked) should expect
/// `staffOnlyGate1NotReady` (or `modelsNotBundled`) for staff-only calls.
public enum OMRHomrIOS {
    /// Stable API target for the app shell.
    ///
    /// - Returns: SMF format 1 @ 480 TPQ + note layout metadata.
    /// - Throws: `OMRError` when models/sessions are missing or staff-only path is not ready.
    public static func parseSheetMusicWithLayout(
        input: ParseSheetMusicInput
    ) throws -> ParseSheetMusicResult {
        let session = try StaffInferenceSession.makeDefault()
        return try session.parse(input: input)
    }
}

public enum OMRError: Error, Equatable, CustomStringConvertible {
    case modelsNotBundled(String)
    case sessionNotConfigured(String)
    case tokenizerMissing(String)
    case staffOnlyGate1NotReady(String)
    case invalidVocabulary(String)

    public var description: String {
        switch self {
        case .modelsNotBundled(let m): return "modelsNotBundled: \(m)"
        case .sessionNotConfigured(let m): return "sessionNotConfigured: \(m)"
        case .tokenizerMissing(let m): return "tokenizerMissing: \(m)"
        case .staffOnlyGate1NotReady(let m): return "staffOnlyGate1NotReady: \(m)"
        case .invalidVocabulary(let m): return "invalidVocabulary: \(m)"
        }
    }
}
