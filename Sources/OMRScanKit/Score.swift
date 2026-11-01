import Foundation

/// One recognized note. Times are in quarter notes (beats) from the start of the score.
struct ScoreNote: Equatable, Codable, Sendable {
    var pitch: Int
    var onset: Double
    var duration: Double
    var velocity: Int
}

struct ScorePart: Equatable, Codable, Sendable {
    var name: String
    var program: Int?
    var notes: [ScoreNote]
}

struct TimeSignature: Equatable, Codable, Sendable {
    var numerator: Int
    var denominator: Int
}

/// Recognizer output: parts plus global tempo (BPM), key (e.g. "C", "Am", "F#") and time signature.
struct Score: Equatable, Codable, Sendable {
    var parts: [ScorePart]
    var tempo: Double?
    var key: String?
    var timeSig: TimeSignature?

    var noteCount: Int { parts.reduce(0) { $0 + $1.notes.count } }
}
