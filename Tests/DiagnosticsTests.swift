import OMRHomrIOS
import XCTest
@testable import OMRSheetCam

/// DiagnosticsLog persistence + cap, PromptBuilder ("Copy as prompt"), OMRFeedback round-trip.
final class DiagnosticsTests: XCTestCase {
    private var dirs: [URL] = []

    override func tearDown() {
        for d in dirs { try? FileManager.default.removeItem(at: d) }
        super.tearDown()
    }

    private func tempDir() -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("diag-\(UUID().uuidString)", isDirectory: true)
        dirs.append(d)
        return d
    }

    private let device = DeviceInfo(model: "iPhone16,1", os: "iOS 18.0.1", appVersion: "1.0", build: "4", ortVersion: "1.24.2")
    private let fixedDate = Date(timeIntervalSince1970: 1_790_000_000)

    private func feedback(capture: String = "20260926-130501-123.jpg") -> OMRFeedback {
        OMRFeedback(
            captureName: capture, verdict: .partlyWrong,
            staffVerdicts: [.init(staffIndex: 0, verdict: .partlyWrong)],
            wrongNotes: [.init(noteIndex: 3, staffIndex: 0, pitch: "F4"), .init(noteIndex: 6, staffIndex: 0, pitch: "B4")],
            note: "F4 and B4 read a step too high", staffCount: 1, noteCount: 8, layoutSource: "midi-fallback", date: fixedDate
        )
    }

    /// Realistic event stream: warmup, Gate-1 npy/png, capture, recognition, repeated errors, feedback.
    private func sampleEvents() throws -> [DiagnosticsEvent] {
        var e: [DiagnosticsEvent] = []
        func add(_ l: DiagnosticsEvent.Level, _ c: DiagnosticsEvent.Category, _ m: String, _ p: [String: String]? = nil) {
            e.append(DiagnosticsEvent(level: l, category: c, message: m, payload: p))
        }
        add(.info, .app, "launch iPhone16,1 · iOS 18.0.1 · v1.0 (4) · ORT 1.24.2")
        add(.info, .warmup, "warmup start: footprint 42 MB", ["kind": "start"])
        add(.info, .warmup, "segnet coreML: create 910 ms, first run 120 ms, footprint 140 MB", ["kind": "session"])
        add(.info, .warmup, "encoder coreML: create 1510 ms, first run 300 ms, footprint 260 MB", ["kind": "session"])
        add(.info, .warmup, "decoder cpu: create 400 ms, first run 35 ms, footprint 330 MB", ["kind": "session"])
        add(.info, .warmup, "warmup ready: total 3275 ms, footprint 42 → 330 MB, peak 335 MB",
            ["kind": "summary", "providers": "segnet=coreML encoder=coreML decoder=cpu"])
        add(.info, .gate1, "npy: PASS 12/12; decode 812 ms, encoder coreML, ORT 1.24.2", ["kind": "result", "input": "npy"])
        add(.info, .gate1, "png: PASS 12/12; decode 790 ms, encoder coreML, ORT 1.24.2, png-npy max|diff| 0.0", ["kind": "result", "input": "png"])
        add(.info, .capture, "saved captures/20260926-130501-123.jpg (3024x4032, 2210 KB, camera)", ["capture": "20260926-130501-123.jpg"])
        add(.info, .recognition, "20260926-130501-123.jpg: comingSoon · 3024x4032 · 2210 KB · 0 ms",
            ["kind": "run", "capture": "20260926-130501-123.jpg", "outcome": "comingSoon"])
        for _ in 0..<3 { add(.warn, .capture, "camera interrupted: Camera in use by another app") }
        add(.error, .playback, "placeholder play (0 B): emptyData")
        e.append(try feedback().event())
        return e
    }

    // MARK: - PromptBuilder

    func testPromptHasAllSections() throws {
        let text = PromptBuilder.build(.init(device: device, events: try sampleEvents()))
        print("---- sample prompt (\(text.utf8.count) bytes) ----\n\(text)---- end sample prompt ----")
        for needle in [
            "# OMR Sheet Cam diagnostics", "Please help diagnose",
            "App v1.0 (4) · iPhone16,1 · iOS 18.0.1", "ORT 1.24.2 · providers: segnet=coreML encoder=coreML decoder=cpu",
            "## Warmup (latest)", "warmup ready: total 3275 ms", "decoder cpu: create 400 ms",
            "## Gate-1 (latest)", "npy: PASS 12/12", "png: PASS 12/12",
            "## Last recognition", "20260926-130501-123.jpg: comingSoon",
            "## Errors & warnings (2 unique, 4 total)", "[warn] capture ×3: camera interrupted", "[error] playback: placeholder play",
            "## OMR accuracy feedback", "Verdict: Partly wrong", "Per staff: staff 1 partly wrong",
            "Wrong-marked notes (2): #3 F4 (staff 1), #6 B4 (staff 1)", "Note: \"F4 and B4 read a step too high\"",
            "Capture: 20260926-130501-123.jpg · staffCount 1 · noteCount 8 · layout midi-fallback",
        ] {
            XCTAssertTrue(text.contains(needle), "missing: \(needle)\n\(text)")
        }
        XCTAssertLessThanOrEqual(text.utf8.count, 4096)
    }

    func testPromptEmptyLogStillHasSections() {
        let text = PromptBuilder.build(.init(device: device, events: []))
        XCTAssertTrue(text.contains("## Warmup (latest)\n- none recorded"))
        XCTAssertTrue(text.contains("## Gate-1 (latest)\n- not run"))
        XCTAssertTrue(text.contains("## Errors & warnings (0 unique, 0 total)\n- none"))
        XCTAssertTrue(text.contains("- none given"))
    }

    func testPromptSizeCapTruncatesWithCounts() throws {
        var events = try sampleEvents()
        for i in 0..<300 {
            events.append(DiagnosticsEvent(level: .error, category: .recognition,
                                           message: "failure \(i): " + String(repeating: "x", count: 300)))
        }
        var f = feedback()
        f.note = String(repeating: "long note ", count: 500)
        f.wrongNotes = (0..<100).map { .init(noteIndex: $0, staffIndex: $0 % 2, pitch: "C4") }
        let text = PromptBuilder.build(.init(device: device, events: events, feedback: f))
        XCTAssertLessThanOrEqual(text.utf8.count, 4096)
        XCTAssertTrue(text.contains("Please help diagnose"))
        XCTAssertTrue(text.contains("(302 unique, 304 total)"), text)
        XCTAssertTrue(text.contains("Wrong-marked notes (100)"), text)
        // Both long lists are cut with a remaining count.
        let more = try NSRegularExpression(pattern: "… and \\d+ more")
        XCTAssertGreaterThanOrEqual(more.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text)), 2, text)
        XCTAssertTrue(text.contains("## OMR accuracy feedback"))
    }

    func testDedupeCountsAndOrder() {
        let e = [
            DiagnosticsEvent(level: .warn, category: .capture, message: "a"),
            DiagnosticsEvent(level: .error, category: .capture, message: "b"),
            DiagnosticsEvent(level: .warn, category: .capture, message: "a"),
            DiagnosticsEvent(level: .error, category: .gate1, message: "a"),
            DiagnosticsEvent(level: .warn, category: .capture, message: "a"),
        ]
        let p = PromptBuilder.dedupe(e)
        XCTAssertEqual(p.map(\.count), [3, 1, 1])
        XCTAssertEqual(p[0].message, "a")
        XCTAssertEqual(p[0].category, .capture)
    }

    func testPromptFeedbackFiltersByCaptureAndPrefersUnsaved() throws {
        let events = [try feedback(capture: "a.jpg").event(), try feedback(capture: "b.jpg").event()]
        let forA = PromptBuilder.build(.init(device: device, events: events, captureName: "a.jpg"))
        XCTAssertTrue(forA.contains("Capture: a.jpg"))
        XCTAssertFalse(forA.contains("Capture: b.jpg"))
        let latest = PromptBuilder.build(.init(device: device, events: events))
        XCTAssertTrue(latest.contains("Capture: b.jpg"))
        var unsaved = feedback(capture: "a.jpg")
        unsaved.verdict = .wrong
        let live = PromptBuilder.build(.init(device: device, events: events, captureName: "a.jpg", feedback: unsaved))
        XCTAssertTrue(live.contains("Verdict: Wrong"))
    }

    // MARK: - Feedback serialization

    func testFeedbackEventRoundTrip() throws {
        let f = feedback()
        let event = try f.event()
        XCTAssertEqual(event.category, .feedback)
        XCTAssertEqual(event.payload?["capture"], "20260926-130501-123.jpg")
        XCTAssertEqual(event.message, "feedback 20260926-130501-123.jpg: Partly wrong, 2 wrong notes")
        let json = try XCTUnwrap(event.payload?[OMRFeedback.payloadKey])
        XCTAssertTrue(json.contains("\"verdict\":\"partly_wrong\""), json)
        XCTAssertEqual(OMRFeedback(event: event), f)
        // Survives the log's JSON-lines encoding too.
        let line = try DiagnosticsLog.encoder.encode(event)
        let back = try DiagnosticsLog.decoder.decode(DiagnosticsEvent.self, from: line)
        XCTAssertEqual(OMRFeedback(event: back), f)
        XCTAssertNil(OMRFeedback(event: DiagnosticsEvent(level: .info, category: .app, message: "x")))
        XCTAssertTrue(OMRFeedback(captureName: "c", staffCount: 0, noteCount: 0).isEmpty)
    }

    // MARK: - DiagnosticsLog

    func testLogPersistsAndReloads() throws {
        let dir = tempDir()
        let log = DiagnosticsLog(directory: dir, mirrorToOSLog: false)
        for i in 0..<5 { log.record(.warn, .capture, "e\(i)", payload: ["i": "\(i)"]) }
        log.record(error: DiagnosticsTestError.boom, category: .recognition, context: "parse")
        log.flush()
        let reloaded = DiagnosticsLog(directory: dir, mirrorToOSLog: false)
        XCTAssertEqual(reloaded.events.map(\.message), ["e0", "e1", "e2", "e3", "e4", "parse: boom"])
        XCTAssertEqual(reloaded.events[2].payload?["i"], "2")
        XCTAssertEqual(reloaded.events.last?.level, .error)
        XCTAssertEqual(reloaded.events.last?.payload?["error"], "boom")
        XCTAssertEqual(reloaded.events.last?.payload?["type"], String(reflecting: DiagnosticsTestError.self))
        XCTAssertEqual(reloaded.events.map(\.id), log.events.map(\.id))
    }

    func testLogEntryCap() throws {
        let dir = tempDir()
        let log = DiagnosticsLog(directory: dir, maxEntries: 50, mirrorToOSLog: false)
        for i in 0..<200 { log.record(.info, .app, "e\(i)") }
        log.flush()
        XCTAssertEqual(log.events.count, 50)
        XCTAssertEqual(log.events.first?.message, "e150")
        let lines = try String(contentsOf: try XCTUnwrap(log.fileURL)).split(separator: "\n").count
        XCTAssertLessThanOrEqual(lines, 62)
        let reloaded = DiagnosticsLog(directory: dir, maxEntries: 50, mirrorToOSLog: false)
        XCTAssertEqual(reloaded.events.count, 50)
        XCTAssertEqual(reloaded.events.first?.message, "e150")
        XCTAssertEqual(reloaded.events.last?.message, "e199")
    }

    func testLogByteCap() throws {
        let dir = tempDir()
        let log = DiagnosticsLog(directory: dir, maxEntries: 1000, maxBytes: 8000, mirrorToOSLog: false)
        for i in 0..<300 { log.record(.info, .app, "e\(i) " + String(repeating: "y", count: 60)) }
        log.flush()
        let url = try XCTUnwrap(log.fileURL)
        let size = try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int)
        XCTAssertLessThanOrEqual(size, 8000)
        let reloaded = DiagnosticsLog(directory: dir, maxEntries: 1000, maxBytes: 8000, mirrorToOSLog: false)
        XCTAssertGreaterThan(reloaded.events.count, 10)
        XCTAssertLessThan(reloaded.events.count, 300)
        XCTAssertTrue(reloaded.events.last?.message.hasPrefix("e299 ") == true)
    }

    func testLogClear() throws {
        let dir = tempDir()
        let log = DiagnosticsLog(directory: dir, mirrorToOSLog: false)
        log.record(.error, .app, "x")
        log.clear()
        log.flush()
        XCTAssertTrue(log.events.isEmpty)
        XCTAssertTrue(DiagnosticsLog(directory: dir, mirrorToOSLog: false).events.isEmpty)
    }

    // MARK: - Call-site payloads

    func testRecognitionEventPayload() {
        let log = DiagnosticsLog(directory: nil, mirrorToOSLog: false)
        ResultScreen.recordRecognition(.comingSoon, capture: "c.jpg", inputBytes: 2048, pixels: "10x20", ms: 1.5, log: log)
        let details = RecognitionDetails(
            midi: Data([1]), notes: [RecognizedNote(noteIndex: 0, symbolIndex: 2, staffIndex: 0, midiNote: 60, onsetTicks: 0, durationTicks: 480)],
            staffCount: 2, warnings: ["skew"], layoutSource: "attention", ms: 900
        )
        ResultScreen.recordRecognition(.recognized(details), capture: "c.jpg", inputBytes: 2048, pixels: "10x20", ms: 950, log: log)
        ResultScreen.recordRecognition(.failed("bad page"), capture: "c.jpg", inputBytes: 2048, pixels: "10x20", ms: 3, log: log)
        let e = log.events
        XCTAssertEqual(e.map(\.level), [.info, .warn, .error])
        XCTAssertEqual(e[0].payload?["outcome"], "comingSoon")
        XCTAssertEqual(e[1].payload?["staff_count"], "2")
        XCTAssertEqual(e[1].payload?["note_count"], "1")
        XCTAssertEqual(e[1].payload?["warnings"], "skew")
        XCTAssertEqual(e[1].payload?["layout_source"], "attention")
        XCTAssertEqual(e[2].payload?["error"], "bad page")
        XCTAssertEqual(e[2].payload?["input_bytes"], "2048")
    }

    func testGate1NotesFromOracleTokens() throws {
        let json = try Gate1Runner.bundledFixturesDir().appendingPathComponent("expected.tokens.json")
        let notes = RecognizedNote.fromSymbols(try Gate1Oracle.loadExpectedSymbols(from: json))
        XCTAssertEqual(notes.map(\.pitchName), ["C4", "D4", "E4", "F4", "G4", "A4", "B4", "C5"])
        XCTAssertEqual(Set(notes.map(\.durationName)), ["quarter"])
        XCTAssertEqual(notes.map(\.symbolIndex), [2, 3, 4, 5, 7, 8, 9, 10])
        XCTAssertEqual(notes.map(\.noteIndex), Array(0..<8))
        XCTAssertTrue(notes.allSatisfy { $0.staffIndex == 0 && $0.rect == nil })
        XCTAssertEqual(RecognizedNote.durationName(ticks: 720), "dotted quarter")
    }
}

private enum DiagnosticsTestError: Error, CustomStringConvertible {
    case boom
    var description: String { "boom" }
}
