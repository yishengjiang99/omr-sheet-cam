import UIKit
import XCTest
@testable import OMRScanKit

/// `ScanRunner`: multi-page merge, monotonic whole-scan progress, cancellation (never reaches the
/// host), the host gate and the failure taxonomy. Fake recognition service, no models.
final class ScanRunnerTests: XCTestCase {
    private static func smf(notes: [(Int, Double)]) -> Data {
        var t = 0.0
        let ns = notes.map { p, d -> ScoreNote in defer { t += d }; return ScoreNote(pitch: p, onset: t, duration: d, velocity: 80) }
        return SMFWriter.data(for: Score(parts: [ScorePart(name: "Staff 1", program: 0, notes: ns)], tempo: 120))
    }

    private static func details(_ pitches: [Int]) -> RecognitionDetails {
        RecognitionDetails(midi: smf(notes: pitches.map { ($0, 1.0) }), notes: [], staffCount: 1, warnings: [],
                           layoutSource: "midiFallback", ms: 1)
    }

    private final class Scripted: RecognitionService, @unchecked Sendable {
        var outcomes: [RecognitionOutcome]
        var reports: [[ScanProgress]]
        var delay: UInt64 = 0
        private(set) var calls = 0
        private let lock = NSLock()
        init(_ outcomes: [RecognitionOutcome], reports: [[ScanProgress]] = []) { self.outcomes = outcomes; self.reports = reports }
        func recognize(imageData: Data) async -> RecognitionOutcome { await recognize(imageData: imageData, progress: { _ in }) }
        func recognize(imageData: Data, progress: @escaping RecognitionProgressHandler) async -> RecognitionOutcome {
            lock.lock(); let i = calls; calls += 1; lock.unlock()
            if i < reports.count { reports[i].forEach(progress) }
            if delay > 0 { await Task.detached { try? await Task.sleep(nanoseconds: self.delay) }.value }
            return outcomes[min(i, outcomes.count - 1)]
        }
    }

    private final class Host: ScanHost, @unchecked Sendable {
        var finished: [ScanResult] = []
        var events: [String] = []
        var allow = true
        var failHandOff = false
        private let lock = NSLock()
        func didFinish(_ result: ScanResult) async throws {
            lock.lock(); finished.append(result); lock.unlock()
            if failHandOff { throw NSError(domain: "studio", code: 1) }
        }
        func shouldBeginScan() async -> Bool { allow }
        func telemetry(_ event: ScanEvent) {
            lock.lock(); defer { lock.unlock() }
            switch event {
            case .started: events.append("started")
            case .progress: break
            case .completed: events.append("completed")
            case let .failed(_, reason, _, _): events.append("failed:\(reason)")
            }
        }
    }

    private final class Statuses: @unchecked Sendable {
        private let lock = NSLock(); private var v: [ScanStatus] = []
        func add(_ s: ScanStatus) { lock.lock(); v.append(s); lock.unlock() }
        var all: [ScanStatus] { lock.lock(); defer { lock.unlock() }; return v }
    }

    func testTwoPagesMergeIntoOneScoreWithPageTwoStartingAtPageOneEnd() async throws {
        let svc = Scripted([.recognized(Self.details([60, 62])), .recognized(Self.details([64]))])
        let host = Host()
        let result = try await ScanRunner(service: svc).run(pages: [Data([1]), Data([2])], host: host)
        XCTAssertEqual(result.pageCount, 2)
        XCTAssertEqual(result.noteCount, 3)
        XCTAssertEqual(result.trackCount, 1)
        let score = try SMFReader.score(from: result.midi)
        let onsets = score.parts[0].notes.sorted { $0.onset < $1.onset }
        XCTAssertEqual(onsets.map(\.pitch), [60, 62, 64])
        XCTAssertEqual(onsets.last?.onset ?? -1, 2.0, accuracy: 0.001, "page 2 starts where page 1 ends (2 beats)")
        XCTAssertEqual(host.finished.count, 1)
        XCTAssertEqual(host.events, ["started", "completed"])
    }

    func testProgressIsMonotonicPerPhaseAcrossPagesAndEndsAtOne() async throws {
        let w = { (f: Double) in ScanProgress(warmingUp: true, fraction: f) }
        let r = { (f: Double) in ScanProgress(warmingUp: false, fraction: f) }
        let svc = Scripted(
            [.recognized(Self.details([60])), .recognized(Self.details([62]))],
            reports: [[w(0.2), w(0.1), w(0.9), r(0.3), r(0.2), r(1)], [r(0.5), r(0.4), r(1)]]
        )
        let seen = Statuses()
        _ = try await ScanRunner(service: svc).run(pages: [Data([1]), Data([2])], onStatus: { seen.add($0) })
        let all = seen.all
        for phase in [ScanPhase.warming, .reading] {
            let f = all.filter { $0.phase == phase }.map(\.fraction)
            XCTAssertEqual(f, f.sorted(), "\(phase) never goes backward")
        }
        XCTAssertEqual(all.first?.phase, .warming)
        XCTAssertEqual(all.last?.fraction, 1.0)
        XCTAssertTrue(all.filter { $0.phase == .reading }.contains { $0.page == 1 && $0.fraction > 0.5 })
    }

    func testCancelMidParseNeverReachesTheHost() async throws {
        let svc = Scripted([.recognized(Self.details([60]))])
        svc.delay = 200_000_000
        let host = Host()
        let task = Task { try await ScanRunner(service: svc).run(pages: [Data([1])], host: host) }
        try await Task.sleep(nanoseconds: 30_000_000)
        task.cancel()
        do { _ = try await task.value; XCTFail("expected cancellation") } catch let e as ScanError {
            XCTAssertEqual(e.kind, .cancelled)
        }
        XCTAssertTrue(host.finished.isEmpty, "a late result must never be handed to the host")
        XCTAssertFalse(host.events.contains { $0.hasPrefix("failed") }, "cancel is not a failure event")
    }

    func testGateRefusesBeforeAnyWork() async {
        let svc = Scripted([.recognized(Self.details([60]))])
        let host = Host(); host.allow = false
        do { _ = try await ScanRunner(service: svc).run(pages: [Data([1])], host: host); XCTFail() } catch let e as ScanError {
            XCTAssertEqual(e.reasonCode, "gated")
        } catch { XCTFail("\(error)") }
        XCTAssertEqual(svc.calls, 0)
    }

    func testHandOffFailureFailsTheScan() async {
        let svc = Scripted([.recognized(Self.details([60]))])
        let host = Host(); host.failHandOff = true
        do { _ = try await ScanRunner(service: svc).run(pages: [Data([1])], host: host); XCTFail() } catch let e as ScanError {
            XCTAssertEqual(e.reasonCode, "handoff_failed")
        } catch { XCTFail("\(error)") }
        XCTAssertEqual(host.events, ["started", "failed:handoff_failed"])
    }

    func testFailureTaxonomyMatchesTelemetryReasonCodes() {
        let cases: [(String, ScanError.Kind, String)] = [
            ("no music staff found on the page (staffCount 0)", .nothingRecognized, "no_staff"),
            ("page staff detection: no noteheads found (homr: 'No noteheads found')", .nothingRecognized, "no_staff"),
            ("recognizer returned empty MIDI", .failed, "empty_midi"),
            ("no notes recognized (2 staffs)", .nothingRecognized, "no_notes"),
            ("modelsNotBundled: models/ missing", .recognizerUnavailable, "models_not_bundled"),
            ("sessionNotConfigured: x", .recognizerUnavailable, "session_not_configured"),
            ("tokenizerMissing: x", .recognizerUnavailable, "tokenizer_missing"),
            ("invalidPixelBuffer: bad", .unreadableInput, "invalid_input"),
            ("image not decodable", .unreadableInput, "invalid_input"),
            ("unsupportedImageFormat: x", .unreadableInput, "unsupported_format"),
            ("cancelled", .cancelled, "cancelled"),
            ("something else", .failed, "parse_error"),
        ]
        for (msg, kind, code) in cases {
            let e = ScanError.classify(msg)
            XCTAssertEqual([e.kind.rawValue, e.reasonCode], [kind.rawValue, code], msg)
        }
    }

    func testSinglePageFailureSurfacesItsOwnReasonAndFiresFailedEvent() async {
        let svc = Scripted([.failed("no music staff found on the page (staffCount 0)")])
        let host = Host()
        do { _ = try await ScanRunner(service: svc).run(pages: [Data([1])], host: host); XCTFail() } catch let e as ScanError {
            XCTAssertEqual(e.reasonCode, "no_staff")
            XCTAssertEqual(e.diagnostics?.failureReason, "no_staff")
        } catch { XCTFail("\(error)") }
        XCTAssertEqual(host.events, ["started", "failed:no_staff"])
        XCTAssertTrue(host.finished.isEmpty)
    }

    func testBadPageIsSkippedWhenAnotherPageHasNotes() async throws {
        let svc = Scripted([.failed("no music staff found on the page (staffCount 0)"), .recognized(Self.details([60]))])
        let result = try await ScanRunner(service: svc).run(pages: [Data([1]), Data([2])])
        XCTAssertEqual(result.noteCount, 1)
        XCTAssertEqual(result.pages.count, 1)
    }

    func testUnavailableRecognizerFailsImmediately() async {
        let svc = Scripted([.failed("modelsNotBundled: x"), .recognized(Self.details([60]))])
        do { _ = try await ScanRunner(service: svc).run(pages: [Data([1]), Data([2])]); XCTFail() } catch let e as ScanError {
            XCTAssertEqual(e.reasonCode, "models_not_bundled")
        } catch { XCTFail("\(error)") }
        XCTAssertEqual(svc.calls, 1, "later pages would fail the same way")
    }

    private struct StudioNotReady: ScanFailureReporting {
        var scanReasonCode: String { "studio_not_ready" }
        var scanMessage: String { "The studio isn't ready to import yet." }
    }

    private final class StudioHost: ScanHost, @unchecked Sendable {
        func didFinish(_ result: ScanResult) async throws { throw StudioNotReady() }
    }

    func testHostErrorCanCarryItsOwnReasonCodeAndMessage() async {
        let svc = Scripted([.recognized(Self.details([60]))])
        do { _ = try await ScanRunner(service: svc).run(pages: [Data([1])], host: StudioHost()); XCTFail() } catch let e as ScanError {
            XCTAssertEqual(e.kind, .handOffFailed)
            XCTAssertEqual(e.reasonCode, "studio_not_ready")
            XCTAssertEqual(e.message, "The studio isn't ready to import yet.")
        } catch { XCTFail("\(error)") }
    }

    func testStartedEventCarriesFirstPagePixelSize() async throws {
        final class Sink: ScanHost, @unchecked Sendable {
            var started: (Int?, Int?)?
            func didFinish(_ result: ScanResult) async throws {}
            func telemetry(_ event: ScanEvent) { if case let .started(_, _, w, h) = event { started = (w, h) } }
        }
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 24), format: fmt).image { _ in }
        let sink = Sink()
        _ = try await ScanRunner(service: Scripted([.recognized(Self.details([60]))]))
            .run(pages: [try XCTUnwrap(img.pngData())], host: sink)
        XCTAssertEqual(sink.started?.0, 40)
        XCTAssertEqual(sink.started?.1, 24)
    }
}
