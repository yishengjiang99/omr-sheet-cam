import Foundation
import OMRHomrIOS
import UIKit
import XCTest
@testable import OMRScanKit

/// `PageRecognitionService`: error paths, outcome mapping, session reuse / serialization, cancel,
/// memory-warning drop and progress monotonicity (fake parsers; no models needed).
final class PageRecognitionServiceTests: XCTestCase {
    private struct Boom: Error, CustomStringConvertible { var description: String { "boom: models unavailable" } }

    /// Fake page session: fixed result or error, counts calls and the max concurrent parses.
    private final class FakeParser: PageParser, @unchecked Sendable {
        let result: ParseSheetMusicResult?
        let delay: TimeInterval
        private let lock = NSLock()
        private var active = 0
        private(set) var calls = 0
        private(set) var maxActive = 0
        private(set) var lastSize: (Int, Int, Int)?

        init(result: ParseSheetMusicResult?, delay: TimeInterval = 0) {
            self.result = result
            self.delay = delay
        }

        func parse(gray8: Data, width: Int, height: Int) throws -> PageParseOutput {
            lock.lock(); active += 1; calls += 1; maxActive = max(maxActive, active); lastSize = (gray8.count, width, height); lock.unlock()
            defer { lock.lock(); active -= 1; lock.unlock() }
            XCTAssertFalse(Thread.isMainThread, "parse must run off the main thread")
            if delay > 0 { Thread.sleep(forTimeInterval: delay) }
            guard let result else { throw Boom() }
            return PageParseOutput(result: result, stages: [.init(name: "segnet", ms: 12), .init(name: "decode", ms: 34)])
        }
    }

    /// Fake page session that reports stage progress like `PageInferenceSession.parsePage` (plus one stale,
    /// lower report the service must drop).
    private final class ProgressParser: PageParser, @unchecked Sendable {
        let result: ParseSheetMusicResult
        init(result: ParseSheetMusicResult) { self.result = result }

        func parse(gray8: Data, width: Int, height: Int) throws -> PageParseOutput {
            try parse(gray8: gray8, width: width, height: height, progress: nil)
        }

        func parse(gray8: Data, width: Int, height: Int, progress: PageParseProgressHandler?) throws -> PageParseOutput {
            progress?(PageParseProgress(stage: .preprocess, completed: 1, total: 1))
            for t in 1...6 { progress?(PageParseProgress(stage: .segnet, completed: t, total: 6)) }
            progress?(PageParseProgress(stage: .segnet, completed: 3, total: 6))  // stale / out of order
            progress?(PageParseProgress(stage: .staffs, completed: 1, total: 1))
            for s in 1...3 { progress?(PageParseProgress(stage: .decode, completed: s, total: 3)) }
            return PageParseOutput(result: result)
        }
    }

    /// Thread-safe list of progress fractions.
    private final class Fractions: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [Double] = []
        func add(_ f: Double) { lock.lock(); items.append(f); lock.unlock() }
        var values: [Double] { lock.lock(); defer { lock.unlock() }; return items }
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        func bump() { lock.lock(); n += 1; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return n }
    }

    private static func goodResult(staffCount: Int = 1, notes: Int = 2) -> ParseSheetMusicResult {
        ParseSheetMusicResult(
            midi: Data("MThd".utf8) + Data([0, 0, 0, 6, 0, 1, 0, 2, 1, 0xE0]),
            noteLayout: (0..<notes).map { NoteLayout(symbolIndex: $0, midiNote: 60 + $0, onsetTicks: $0 * 480, durationTicks: 480, pageRect: .null, staffIndex: 0, noteIndex: $0) },
            layoutSource: .midiFallback, staffCount: staffCount,
            warnings: ["layout: midi-fallback (no attention boxes; pageRect is .null)"]
        )
    }

    /// Small valid PNG (content irrelevant for fakes).
    private static func pngData(width: Int = 31, height: Int = 17) -> Data {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }.pngData()!
    }

    private func makeService(

        factory: @escaping PageRecognitionService.SessionFactory, log: DiagnosticsLog,

        center: NotificationCenter = NotificationCenter(), released: Counter = Counter()

    ) -> PageRecognitionService {
        PageRecognitionService(
            factory: factory, releaseShared: { released.bump() }, log: log, notificationCenter: center, sampleInterval: 0.01
        )
    }

    private func pageEvents(_ log: DiagnosticsLog) -> [DiagnosticsEvent] {
        log.events.filter { $0.category == .recognition && $0.payload?["kind"] == "page_parse" }
    }

    // MARK: - Error paths

    // MARK: - Session reuse, serialization, memory warning

    // MARK: - Diagnostics

    // MARK: - Real models (simulator CI): app path vs homr oracle pages

    // MARK: - Progress ("Reading music… 42%")

    func testSessionFactoryErrorGivesFailedOutcomeAndLogsError() async throws {
        let log = DiagnosticsLog(directory: nil, mirrorToOSLog: false)
        let service = makeService(factory: { throw Boom() }, log: log)
        let outcome = await service.recognize(imageData: Self.pngData())
        guard case let .failed(msg) = outcome else { return XCTFail("expected .failed, got \(outcome)") }
        XCTAssertTrue(msg.contains("boom"), msg)
        let e = try XCTUnwrap(pageEvents(log).last)
        XCTAssertEqual(e.level, .error)
        XCTAssertEqual(e.payload?["outcome"], "failed")
        XCTAssertEqual(e.payload?["error"], "boom: models unavailable")
        XCTAssertEqual(e.payload?["image"], "31x17", "image decoded before the session is needed")
        XCTAssertNotNil(e.payload?["footprint_before_mb"])
        XCTAssertNotNil(e.payload?["peak_mb"])
        let built = await service.engine.buildCount
        XCTAssertEqual(built, 0)
    }

    func testUndecodableImageFailsWithoutBuildingSession() async throws {
        let log = DiagnosticsLog(directory: nil, mirrorToOSLog: false)
        let fake = FakeParser(result: Self.goodResult())
        let service = makeService(factory: { fake }, log: log)
        let outcome = await service.recognize(imageData: Data([0xFF, 0xD8, 0x00]))
        guard case .failed = outcome else { return XCTFail("expected .failed, got \(outcome)") }
        let built = await service.engine.buildCount
        XCTAssertEqual(built, 0)
        XCTAssertEqual(fake.calls, 0)
        XCTAssertNotNil(pageEvents(log).last?.payload?["error_type"])
    }

    func testParserErrorGivesFailed() async {
        let log = DiagnosticsLog(directory: nil, mirrorToOSLog: false)
        let fake = FakeParser(result: nil)
        let outcome = await makeService(factory: { fake }, log: log).recognize(imageData: Self.pngData())
        XCTAssertEqual(outcome, .failed("boom: models unavailable"))
        XCTAssertEqual(pageEvents(log).last?.level, .error)
    }

    func testOutcomeMapping() {
        guard case .failed = PageRecognitionService.outcome(for: Self.goodResult(staffCount: 0), ms: 1) else {
            return XCTFail("staffCount 0 must fail")
        }
        guard case .failed = PageRecognitionService.outcome(for: Self.goodResult(notes: 0), ms: 1) else {
            return XCTFail("no notes must fail")
        }
        var empty = Self.goodResult()
        empty.midi = Data()
        guard case .failed = PageRecognitionService.outcome(for: empty, ms: 1) else { return XCTFail("empty MIDI must fail") }
        guard case let .recognized(d) = PageRecognitionService.outcome(for: Self.goodResult(), ms: 42) else {
            return XCTFail("good result must be recognized")
        }
        XCTAssertEqual(d.staffCount, 1)
        XCTAssertEqual(d.notes.count, 2)
        XCTAssertEqual(d.ms, 42)
        XCTAssertFalse(d.hasBoxes, "null pageRect → no highlight boxes")
        XCTAssertTrue(d.notes.allSatisfy { $0.rect == nil })
    }

    func testSessionBuiltOnceReusedAndParsesSerialized() async throws {
        let log = DiagnosticsLog(directory: nil, mirrorToOSLog: false)
        let fake = FakeParser(result: Self.goodResult(), delay: 0.05)
        let builds = Counter()
        let service = makeService(factory: { builds.bump(); return fake }, log: log)
        let png = Self.pngData()
        let outcomes = await withTaskGroup(of: RecognitionOutcome.self) { group -> [RecognitionOutcome] in
            for _ in 0..<3 { group.addTask { await service.recognize(imageData: png) } }
            var all: [RecognitionOutcome] = []
            for await o in group { all.append(o) }
            return all
        }
        XCTAssertEqual(outcomes.map(\.name), ["recognized", "recognized", "recognized"])
        XCTAssertEqual(builds.value, 1, "session must be created once and reused")
        XCTAssertEqual(fake.calls, 3)
        XCTAssertEqual(fake.maxActive, 1, "parses must run one at a time")
        XCTAssertEqual(fake.lastSize.map { [$0.0, $0.1, $0.2] }, [31 * 17, 31, 17])
        XCTAssertEqual(pageEvents(log).compactMap { $0.payload?["session"] }, ["built", "reused", "reused"])
    }

    func testCancelledQueuedRecognizeSkipsParse() async throws {
        let log = DiagnosticsLog(directory: nil, mirrorToOSLog: false)
        let fake = FakeParser(result: Self.goodResult(), delay: 0.3)
        let service = makeService(factory: { fake }, log: log)
        let png = Self.pngData()
        let t1 = Task { await service.recognize(imageData: png) }
        // Wait until t1 is inside the parse (it holds the mutex for `delay`).
        for _ in 0..<200 where fake.calls == 0 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(fake.calls, 1, "t1 must be inside the parse before t2 starts")
        let t2 = Task { await service.recognize(imageData: png) }
        try await Task.sleep(nanoseconds: 50_000_000) // t2 queues in acquire() behind t1
        t2.cancel()
        let o1 = await t1.value
        let o2 = await t2.value
        XCTAssertEqual(o1.name, "recognized")
        XCTAssertEqual(o2, .failed("cancelled"))
        XCTAssertEqual(fake.calls, 1, "cancelled queued task must not run a parse")
    }

    /// F6.8: Cancel during the (non-abortable) parse must discard the late result, and the next scan
    /// only waits for the remaining parse time (no extra queueing behind a zombie).
    func testCancelDuringParseDiscardsResultAndNextScanRuns() async throws {
        let log = DiagnosticsLog(directory: nil, mirrorToOSLog: false)
        let fake = FakeParser(result: Self.goodResult(), delay: 0.3)
        let service = makeService(factory: { fake }, log: log)
        let png = Self.pngData()
        let t1 = Task { await service.recognize(imageData: png) }
        for _ in 0..<200 where fake.calls == 0 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(fake.calls, 1, "t1 must be inside the parse")
        t1.cancel()
        let started = Date()
        let t2 = Task { await service.recognize(imageData: png) }
        let o1 = await t1.value
        let o2 = await t2.value
        XCTAssertEqual(o1, .failed("cancelled"), "a result that arrives after Cancel must be discarded")
        XCTAssertEqual(o2.name, "recognized", "the next scan is not blocked forever / poisoned by the cancelled one")
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.3 + 0.3 + 0.5, "next scan waits at most for the in-flight parse + its own")
        XCTAssertEqual(fake.calls, 2)
    }

    /// F6.8: Cancel while the session is still being built / warmed up must not start the parse.
    func testCancelBeforeParseStartsSkipsParse() async throws {
        let log = DiagnosticsLog(directory: nil, mirrorToOSLog: false)
        let fake = FakeParser(result: Self.goodResult(), delay: 0.05)
        let service = makeService(factory: { try? await Task.sleep(nanoseconds: 300_000_000); return fake }, log: log)
        let t1 = Task { await service.recognize(imageData: Self.pngData()) }
        try await Task.sleep(nanoseconds: 80_000_000) // t1 is inside the (slow) session build
        t1.cancel()
        let o1 = await t1.value
        XCTAssertEqual(o1, .failed("cancelled"))
        XCTAssertEqual(fake.calls, 0, "cancelled before the parse: no parse may run")
        let e = try XCTUnwrap(pageEvents(log).last)
        XCTAssertEqual(e.payload?["cancelled"], "1")
        XCTAssertEqual(e.level, .info, "a user cancel is not an error")
    }

    func testMemoryWarningDropsSessionAndNextParseRebuilds() async throws {
        let log = DiagnosticsLog(directory: nil, mirrorToOSLog: false)
        let center = NotificationCenter()
        let released = Counter()
        let fake = FakeParser(result: Self.goodResult())
        let builds = Counter()
        let service = makeService(factory: { builds.bump(); return fake }, log: log, center: center, released: released)
        _ = await service.recognize(imageData: Self.pngData())
        var has = await service.engine.hasSession
        XCTAssertTrue(has)

        center.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        for _ in 0..<200 where has {
            try await Task.sleep(nanoseconds: 10_000_000)
            has = await service.engine.hasSession
        }
        XCTAssertFalse(has, "memory warning must drop the session")
        XCTAssertEqual(released.value, 1, "warm sessions released too")
        XCTAssertTrue(log.events.contains { $0.payload?["kind"] == "page_session_drop" })

        _ = await service.recognize(imageData: Self.pngData())
        XCTAssertEqual(builds.value, 2)
        XCTAssertEqual(pageEvents(log).last?.payload?["session"], "rebuilt after memory warning")
    }

    /// Service-level progress from the pipeline's stage reports: strictly increasing, ends at exactly 1.0,
    /// stale lower reports dropped.
    func testRecognitionProgressOnlyGoesUpAndEndsAt100() async throws {
        let log = DiagnosticsLog(directory: nil, mirrorToOSLog: false)
        let parser = ProgressParser(result: Self.goodResult())
        let service = makeService(factory: { parser }, log: log)
        let got = Fractions()
        let outcome = await service.recognize(imageData: Self.pngData()) { got.add($0.fraction) }
        guard case .recognized = outcome else { return XCTFail("expected recognized, got \(outcome)") }
        let f = got.values
        XCTAssertGreaterThanOrEqual(f.count, 11, "preprocess + 6 tiles + staffs + 3 staffs: \(f)")
        for (a, b) in zip(f, f.dropFirst()) { XCTAssertLessThan(a, b, "progress went down or repeated: \(f)") }
        XCTAssertEqual(f.last, 1.0)
        XCTAssertTrue(f.allSatisfy { $0 >= 0 && $0 <= 1 })
    }



    /// Monotonic gate: phase change resets the high-water mark so the parse phase restarts at 0.
    func testMonotonicProgressResetsOnPhaseChange() {
        var got: [ScanProgress] = []
        let gate = MonotonicProgress { got.append($0) }
        gate.report(ScanProgress(warmingUp: true, fraction: 0.5))
        gate.report(ScanProgress(warmingUp: true, fraction: 0.4))
        gate.report(ScanProgress(warmingUp: false, fraction: 0.1))
        XCTAssertEqual(got.map(\.fraction), [0.5, 0.1])
        XCTAssertEqual(got.map(\.warmingUp), [true, false])
    }

    /// Failed parse: progress never claims 100%.
    func testFailedRecognitionDoesNotReport100() async {
        let log = DiagnosticsLog(directory: nil, mirrorToOSLog: false)
        let service = makeService(factory: { FakeParser(result: nil) }, log: log)
        let got = Fractions()
        let outcome = await service.recognize(imageData: Self.pngData()) { got.add($0.fraction) }
        XCTAssertEqual(outcome.name, "failed")
        XCTAssertFalse(got.values.contains(1.0))
    }

}
