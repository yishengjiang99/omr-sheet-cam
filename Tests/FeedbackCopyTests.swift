import XCTest
@testable import OMRSheetCam

/// F8.7: the "Was the reading accurate?" feedback is only written to the on-device diagnostics log
/// (`DiagnosticsLog` events.jsonl); nothing is uploaded. The UI must not imply it was submitted.
final class FeedbackCopyTests: XCTestCase {
    private func source(_ rel: String) throws -> String {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: repo.appendingPathComponent(rel), encoding: .utf8)
    }

    /// Every user-visible literal in OMRCompareView.swift that says feedback was "saved" must also say
    /// where: "device". (Source lint: `save()` is private to a SwiftUI view, so the literal is the
    /// observable surface; `testFeedbackCopyConstants` below checks the real strings once they are constants.)
    func testNoSavedLiteralWithoutSayingOnDevice() throws {
        let src = try source("Sources/App/Diagnostics/OMRCompareView.swift")
        let literals = src.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .flatMap { line -> [String] in
                var out: [String] = [], cur: String?
                var prev: Character = " "
                for ch in line {
                    if ch == "\"" && prev != "\\" { if let c = cur { out.append(c); cur = nil } else { cur = "" } }
                    else if cur != nil { cur!.append(ch) }
                    prev = ch
                }
                return out
            }
        let saved = literals.filter { $0.localizedCaseInsensitiveContains("saved") || $0.localizedCaseInsensitiveContains("save feedback") }
        XCTAssertFalse(saved.isEmpty, "expected the save toast/button copy to be found in the source")
        for l in saved {
            XCTAssertTrue(l.localizedCaseInsensitiveContains("device"), "'\(l)' implies feedback was submitted; say it is stored on this device only")
        }
    }

    func testFeedbackCopyConstants() {
        typealias C = OMRCompareView.FeedbackCopy
        for text in [C.sectionFooter, C.saveButton, C.savedToast, C.failedToast] {
            XCTAssertTrue(text.localizedCaseInsensitiveContains("device"), text)
            for banned in ["submitted", "sent to us", "thank", "Feedback saved"] {
                XCTAssertFalse(text.localizedCaseInsensitiveContains(banned), "\(text) contains \(banned)")
            }
        }
        XCTAssertTrue(C.sectionFooter.contains("Nothing is sent"))
        XCTAssertEqual(C.sectionTitle, "Was the reading accurate?")
    }
}
