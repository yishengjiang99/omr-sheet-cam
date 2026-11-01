import CoreGraphics
import Foundation
import OMRHomrIOS
import OMRScanKit

/// User's OMR accuracy feedback for one capture (stored as a `feedback` log event).
struct OMRFeedback: Codable, Equatable, Sendable {
    enum Verdict: String, Codable, CaseIterable, Sendable {
        case accurate
        case partlyWrong = "partly_wrong"
        case wrong

        var label: String {
            switch self {
            case .accurate: return "Accurate"
            case .partlyWrong: return "Partly wrong"
            case .wrong: return "Wrong"
            }
        }
    }

    struct StaffVerdict: Codable, Equatable, Sendable {
        var staffIndex: Int
        var verdict: Verdict
    }

    struct WrongNote: Codable, Equatable, Sendable {
        var noteIndex: Int
        var staffIndex: Int
        var pitch: String
    }

    /// Capture file name (`20260926-130501-123.jpg`) or `gate1/staff.png`.
    var captureName: String
    var verdict: Verdict?
    var staffVerdicts: [StaffVerdict] = []
    var wrongNotes: [WrongNote] = []
    var note: String = ""
    var staffCount: Int
    var noteCount: Int
    var layoutSource: String?
    var date: Date = Date()

    var isEmpty: Bool { verdict == nil && staffVerdicts.isEmpty && wrongNotes.isEmpty && note.isEmpty }

    var summary: String {
        var s = "feedback \(captureName): \(verdict?.label ?? "no verdict")"
        if !wrongNotes.isEmpty { s += ", \(wrongNotes.count) wrong note\(wrongNotes.count == 1 ? "" : "s")" }
        return s
    }

    // MARK: - Log event round-trip

    static let payloadKey = "feedback_json"

    func event() throws -> DiagnosticsEvent {
        let json = String(decoding: try DiagnosticsLog.encoder.encode(self), as: UTF8.self)
        return DiagnosticsEvent(
            level: .info, category: .feedback, message: summary,
            payload: [Self.payloadKey: json, "capture": captureName]
        )
    }

    init(captureName: String, verdict: Verdict? = nil, staffVerdicts: [StaffVerdict] = [], wrongNotes: [WrongNote] = [],
         note: String = "", staffCount: Int, noteCount: Int, layoutSource: String? = nil, date: Date = Date()) {
        self.captureName = captureName
        self.verdict = verdict
        self.staffVerdicts = staffVerdicts
        self.wrongNotes = wrongNotes
        self.note = note
        self.staffCount = staffCount
        self.noteCount = noteCount
        self.layoutSource = layoutSource
        self.date = date
    }

    init?(event: DiagnosticsEvent) {
        guard event.category == .feedback, let json = event.payload?[Self.payloadKey],
              let f = try? DiagnosticsLog.decoder.decode(OMRFeedback.self, from: Data(json.utf8)) else { return nil }
        self = f
    }
}
