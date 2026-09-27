import Foundation
import OMRHomrIOS
import UIKit
import XCTest
@testable import OMRSheetCam

/// `PageRecognitionService`: error paths, outcome mapping, session reuse / serialization, memory
/// warning drop, `page_parse` diagnostics + prompt section, and (when models are available) a real
/// full-page parse of the C-scale fixture page.
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

    // MARK: - Session reuse, serialization, memory warning

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

    // MARK: - Diagnostics

    func testPageParseDiagnosticsFieldsAndPromptSection() async throws {
        let log = DiagnosticsLog(directory: nil, mirrorToOSLog: false)
        let fake = FakeParser(result: Self.goodResult(), delay: 0.05)
        let outcome = await makeService(factory: { fake }, log: log).recognize(imageData: Self.pngData())
        XCTAssertEqual(outcome.name, "recognized")
        let e = try XCTUnwrap(pageEvents(log).last)
        let p = try XCTUnwrap(e.payload)
        for key in ["ms", "decode_ms", "parse_ms", "image_w", "image_h", "staff_count", "warnings_count",
                    "footprint_before_mb", "footprint_after_mb", "peak_mb", "peak_source", "sampled_peak_mb", "samples", "stages"] {
            XCTAssertNotNil(p[key], "missing \(key) in \(p)")
        }
        XCTAssertEqual(p["image_w"], "31")
        XCTAssertEqual(p["image_h"], "17")
        XCTAssertEqual(p["staff_count"], "1")
        XCTAssertEqual(p["warnings_count"], "1")
        XCTAssertEqual(p["stages"], "segnet=12 decode=34")
        XCTAssertGreaterThan(Double(p["peak_mb"] ?? "0") ?? 0, 0)
        XCTAssertGreaterThanOrEqual(Double(p["peak_mb"] ?? "0") ?? 0, Double(p["footprint_before_mb"] ?? "0") ?? 0)
        XCTAssertGreaterThanOrEqual(Int(p["samples"] ?? "0") ?? 0, 2, "sampled during the parse")
        print("PageParse diag: \(e.message)")

        let device = DeviceInfo(model: "iPhone16,1", os: "iOS 18.0", appVersion: "1.0", build: "6", ortVersion: "1.24.2")
        let text = PromptBuilder.build(.init(device: device, events: log.events))
        print("---- prompt ----\n\(text)---- end ----")
        XCTAssertTrue(text.contains("## Page parse (latest)\n- recognized · "), text)
        XCTAssertTrue(text.contains("image 31x17 · staffCount 1 · warnings 1"), text)
        XCTAssertTrue(text.contains("memory (phys_footprint): before "), text)
        XCTAssertTrue(text.contains("stages ms: segnet=12 decode=34"), text)
        XCTAssertLessThanOrEqual(text.utf8.count, 4096)
        let empty = PromptBuilder.build(.init(device: device, events: []))
        XCTAssertTrue(empty.contains("## Page parse (latest)\n- none"))
    }

    func testAppUsesPageRecognition() {
        XCTAssertTrue((AppServices.recognition as? GatedRecognitionService)?.real is PageRecognitionService)
    }

    /// "Try sample picture": ode-to-joy.jpg is bundled and decodes to an upright page image that
    /// the Result flow can feed to `AppServices.recognition`.
    func testTrySamplePictureIsBundledAndDecodes() async throws {
        XCTAssertEqual(SamplePicture.buttonTitle, "Try sample picture")
        XCTAssertEqual(SamplePicture.resourceName, "ode-to-joy")
        let data = try SamplePicture.data()
        XCTAssertGreaterThan(data.count, 50_000)
        let photo = try await SamplePicture.photo()
        XCTAssertEqual(photo.source, .sample)
        XCTAssertEqual(photo.image.imageOrientation, .up)
        XCTAssertGreaterThanOrEqual(photo.image.size.width * photo.image.scale, 1200, "LilyPond render ~1530 px wide")
    }

    // MARK: - Real models (simulator CI): app path vs homr oracle pages

    /// `fixtures/oracle.pages/<id>/stages.json` (homr 7d97c3c): input image, staffs, voices.
    struct OraclePage {
        var id: String
        var input: URL
        var expectedStaffCount: Int
        var expectedPitches: [Int]
    }

    private struct Stages: Decodable {
        struct Staff: Decodable { var is_grandstaff: Bool }
        struct SegNet: Decodable { var class_counts: [Int]; var shape: [Int] }
        var segnet: SegNet?
        var fixture: String
        var input_image: String
        var staffs: [Staff]
        var voices: [[OracleSymbolFields]]
    }

    static func oraclePages() throws -> [OraclePage] {
        let root = Gate1StaffTokenMatchTests.repoRoot
        let dir = root.appendingPathComponent("fixtures/oracle.pages")
        let ids = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
        return try ids.compactMap { id -> OraclePage? in
            let url = dir.appendingPathComponent(id).appendingPathComponent("stages.json")
            guard let data = try? Data(contentsOf: url) else { return nil }
            let st = try JSONDecoder().decode(Stages.self, from: data)
            // ParseSheetMusicResult.staffCount = SMF staff tracks: one per voice, two for a grand-staff voice.
            let staffCount = st.voices.count + st.staffs.filter(\.is_grandstaff).count
            let pitches = st.voices.flatMap { v in
                RecognizedNote.fromSymbols(v.map { EncodedSymbol(oracleFields: $0) }).compactMap(\.midiNote)
            }.sorted()
            return OraclePage(id: st.fixture, input: root.appendingPathComponent(st.input_image),
                              expectedStaffCount: staffCount, expectedPitches: pitches)
        }
    }

    /// Skips (like Gate-1) when the pinned models are not reachable.
    private func requireModels() throws -> URL {
        do {
            let dir = try ModelWarmup.resolveModelsDir(nil)
            _ = try PageModels.files(in: dir)
            return dir
        } catch {
            throw XCTSkip("pinned models not available (\(error)); run scripts/fetch-models or set OMR_MODELS_DIR")
        }
    }

    private func realService(_ log: DiagnosticsLog) -> PageRecognitionService {
        PageRecognitionService(factory: PageRecognitionService.warmedSession, releaseShared: {}, log: log,
                               notificationCenter: NotificationCenter())
    }

    /// C-scale page (`fixtures/mono.c_major_scale/input.png`) through the app path: ImageIO →
    /// `Gray8Image` → `PageInferenceSession` on the warmed sessions. homr: 1 staff, C4…C5.
    @MainActor
    func testCScalePageFullParseOnWarmedSessions() async throws {
        let png = Gate1StaffTokenMatchTests.repoRoot.appendingPathComponent("fixtures/mono.c_major_scale/input.png")
        guard let data = try? Data(contentsOf: png) else { throw XCTSkip("fixture page missing: \(png.path)") }
        let dir = try requireModels()
        let log = DiagnosticsLog(directory: nil, mirrorToOSLog: false)
        let outcome = await realService(log).recognize(imageData: data)
        let e = pageEvents(log).last
        print("PageParse mono.c_major_scale: \(e?.message ?? "no event") | \(e?.payload ?? [:])")
        guard case let .recognized(d) = outcome else { return XCTFail("expected recognized, got \(outcome) (models \(dir.path))") }
        XCTAssertEqual(d.staffCount, 1)
        XCTAssertFalse(d.midi.isEmpty)
        XCTAssertEqual(Array(d.midi.prefix(4)), Array("MThd".utf8))
        XCTAssertEqual(d.notes.compactMap(\.midiNote), [60, 62, 64, 65, 67, 69, 71, 72], "homr C-scale pitches")
        XCTAssertFalse(d.hasBoxes, "noteLayout has no page positions yet")
        XCTAssertEqual(e?.payload?["staff_count"], "1")
        XCTAssertEqual(e?.payload?["source_format"]?.hasPrefix("gray 8bpc 1654x2339"), true, e?.payload?["source_format"] ?? "")

        // Tokens: the same warmed sessions through the package page API; staff 0 raw decoder output must equal
        // homr's Gate-1 staff oracle (`fixtures/oracle.c_scale_staff/expected.tokens.json`, 12 symbols).
        let expected = try Gate1Oracle.loadExpectedSymbols(
            from: Gate1StaffTokenMatchTests.repoRoot.appendingPathComponent("fixtures/oracle.c_scale_staff/expected.tokens.json"))
        let factory = PageRecognitionService.warmedSession
        let r = try await Task.detached(priority: .userInitiated) { () -> PageParseResult in
            guard let session = try await factory() as? PageInferenceSession else {
                throw XCTSkip("warmed session is not a PageInferenceSession")
            }
            let g = try Gray8Image.decode(imageData: data)
            return try session.parsePage(gray8: g.pixels, width: g.width, height: g.height)
        }.value
        let got = r.staffSymbols.first ?? []
        let matched = Gate1Oracle.matchedCount(got, expected)
        let timings = r.timings.map { "\($0.stage) \(String(format: "%.0f", $0.ms)) ms" }.joined(separator: ", ")
        print("PageParse mono.c_major_scale tokens: staffs \(r.layout.staffs.count), staff0 \(matched)/\(expected.count) tokens (got \(got.count)) | \(timings)")
        XCTAssertEqual(r.layout.staffs.count, 1)
        XCTAssertNil(Gate1Oracle.firstMismatch(got, expected), "staff 0 tokens \(matched)/\(expected.count) vs homr")
    }

    /// "Try sample picture" end to end: the bundled Ode to Joy page through the same
    /// `PageRecognitionService.recognize(imageData:)` the Result screen uses (warmed sessions) must
    /// recognize at least one staff and some notes. Melody range is C4...G4 (MIDI 60...67).
    @MainActor
    func testTrySamplePictureRecognizesNotes() async throws {
        let data = try SamplePicture.data()
        let dir = try requireModels()
        let log = DiagnosticsLog(directory: nil, mirrorToOSLog: false)
        let outcome = await realService(log).recognize(imageData: data)
        let e = pageEvents(log).last
        print("PageParse sample ode-to-joy: \(e?.message ?? "no event") | \(e?.payload ?? [:])")
        guard case let .recognized(d) = outcome else { return XCTFail("expected recognized, got \(outcome) (models \(dir.path))") }
        let pitches = d.notes.compactMap(\.midiNote)
        print("PageParse sample ode-to-joy: staffCount \(d.staffCount) · notes \(pitches.count) · \(pitches)")
        XCTAssertGreaterThanOrEqual(d.staffCount, 1)
        XCTAssertGreaterThan(pitches.count, 0)
        XCTAssertFalse(d.midi.isEmpty)
    }

    /// Every other homr oracle page through the app path. Hard: recognized + staffCount == homr.
    /// Pitch multiset vs homr's voices is reported per page (printed summary) and asserted too.
    /// ~50 s per page in Debug on the CI simulator: runs only with `OMR_ORACLE_PAGES=1`
    /// (ios-sim.yml workflow_dispatch input `oracle_pages`).
    @MainActor
    func testOraclePagesMatchHomrOnAppPath() async throws {
        guard ProcessInfo.processInfo.environment["OMR_ORACLE_PAGES"] == "1" else {
            throw XCTSkip("set OMR_ORACLE_PAGES=1 (ios-sim.yml dispatch input oracle_pages) to parse all 8 other oracle pages")
        }
        let pages = try Self.oraclePages().filter { $0.id != "mono.c_major_scale" }
        guard !pages.isEmpty else { throw XCTSkip("no fixtures/oracle.pages/*/stages.json") }
        _ = try requireModels()
        let log = DiagnosticsLog(directory: nil, mirrorToOSLog: false)
        let service = realService(log)
        var summary: [String] = []
        for page in pages {
            guard let data = try? Data(contentsOf: page.input) else {
                XCTFail("\(page.id): input missing \(page.input.path)"); continue
            }
            let outcome = await service.recognize(imageData: data)
            let p = pageEvents(log).last?.payload ?? [:]
            let diag = "ms \(p["ms"] ?? "?") · \(p["image"] ?? "?") · peak \(p["peak_mb"] ?? "?") MB · stages \(p["stages"] ?? "-")"
            guard case let .recognized(d) = outcome else {
                summary.append("\(page.id): FAILED \(outcome) · \(diag)")
                XCTFail("\(page.id): expected recognized, got \(outcome) | \(p)")
                continue
            }
            let got = d.notes.compactMap(\.midiNote).sorted()
            let staffOK = d.staffCount == page.expectedStaffCount
            let pitchOK = got == page.expectedPitches
            summary.append("\(page.id): staffCount \(d.staffCount)/\(page.expectedStaffCount) \(staffOK ? "ok" : "MISMATCH") · notes \(got.count)/\(page.expectedPitches.count) pitches \(pitchOK ? "ok" : "MISMATCH got \(got) want \(page.expectedPitches)") · \(diag)")
            XCTAssertEqual(d.staffCount, page.expectedStaffCount, "\(page.id) staffCount")
            XCTAssertEqual(got, page.expectedPitches, "\(page.id) pitches (sorted) vs homr voices")
            XCTAssertFalse(d.midi.isEmpty, page.id)
        }
        summary.forEach { print("OraclePages: \($0)") }
    }

    /// C-scale page → `PagePipeline.preprocess` → SegNet on the warmed CoreML EP session vs a CPU EP session →
    /// class counts vs homr (`stages.json` segnet.class_counts), then staff detection on each map (grep
    /// "SegNetDiag" in the CI log). Regression guard for the all-class-0 CoreML bug (MLProgram): the warmed
    /// session (`SegNetSession.openBackend`, NeuralNetwork 0x000) must give the CPU EP's class counts.
    @MainActor
    func testSegNetClassCountsCoreMLvsCPUvsHomr() async throws {
        let root = Gate1StaffTokenMatchTests.repoRoot
        let stagesURL = root.appendingPathComponent("fixtures/oracle.pages/mono.c_major_scale/stages.json")
        guard let stagesData = try? Data(contentsOf: stagesURL) else { throw XCTSkip("no stages.json") }
        let dir = try requireModels()
        let st = try JSONDecoder().decode(Stages.self, from: stagesData)
        let homr = try XCTUnwrap(st.segnet?.class_counts)
        let data = try Data(contentsOf: root.appendingPathComponent(st.input_image))
        let models = try await ModelWarmup.shared.readyModels()
        let segnetFile = try PageModels.files(in: dir).segnet
        let homrShape = st.segnet?.shape ?? []
        let (lines, coreMLCounts, cpuCounts) = try await Task.detached(priority: .userInitiated) { () -> ([String], [Int], [Int]) in
            let g = try Gray8Image.decode(imageData: data)
            let page = try PagePipeline.preprocess(gray8: g.pixels, width: g.width, height: g.height)
            var out = ["page \(page.width)x\(page.height) (homr \(homrShape))"]
            func run(_ name: String, _ backend: ORTSessionBackend) throws -> [Int] {
                let t = DispatchTime.now()
                let map = try PagePipeline.segment(page, segnet: SegNetSession(backend: backend))
                var counts = [Int](repeating: 0, count: SegNetSession.classCount)
                for c in map where Int(c) < counts.count { counts[Int(c)] += 1 }
                let detect: String
                do {
                    let layout = try PagePipeline.detectStaffs(segmentation: map, width: page.width, height: page.height)
                    detect = "\(layout.staffs.count) staff(s)"
                } catch {
                    detect = "detectStaffs error: \(error)"
                }
                out.append("\(name): classes \(counts) · \(String(format: "%.0f", ModelWarmup.ms(since: t))) ms · \(detect)")
                return counts
            }
            let coreML = try run("coreML (warmed, \(models.segnet.provider) \(models.segnet.coreMLModelFormat ?? "-"))", models.segnet)
            let cpu = try run("cpu", ORTCSession(modelURL: segnetFile, provider: .cpu))
            out.append("homr: classes \(homr)")
            out.append("L1 vs homr: coreML \(zip(coreML, homr).map { abs($0 - $1) }.reduce(0, +)) px, cpu \(zip(cpu, homr).map { abs($0 - $1) }.reduce(0, +)) px")
            return (out, coreML, cpu)
        }.value
        lines.forEach { print("SegNetDiag: \($0)") }
        XCTAssertEqual(lines.count, 5)
        XCTAssertEqual(models.segnet.coreMLModelFormat ?? "cpu", "NeuralNetwork", "warmed SegNet format")
        XCTAssertEqual(coreMLCounts, cpuCounts, "SegNet CoreML EP class counts vs CPU EP")
    }
}
