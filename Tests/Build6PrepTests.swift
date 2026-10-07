import OMRHomrIOS
import UIKit
import XCTest
@testable import OMRSheetCam

/// Build 6 prep: recognition always on, CoreML cache folder, SegNet self-test + its prompt section.
final class Build6PrepTests: XCTestCase {
    private var cleanup: [() -> Void] = []

    override func tearDown() {
        cleanup.forEach { $0() }
        cleanup = []
        super.tearDown()
    }

    private func scratchDefaults() -> UserDefaults {
        let name = "b6-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        cleanup.append { d.removePersistentDomain(forName: name) }
        return d
    }

    private func tempDir() -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("b6-\(UUID().uuidString)", isDirectory: true)
        cleanup.append { try? FileManager.default.removeItem(at: d) }
        return d
    }

    // MARK: - Recognition always on (no developer gate)

    func testAppRecognitionIsPageService() {
        XCTAssertTrue(AppServices.recognition is PageRecognitionService)
    }

    func testLegacyExperimentalKeyIsCleared() {
        let d = scratchDefaults()
        d.set(false, forKey: AppServices.legacyExperimentalRecognitionKey)
        XCTAssertNotNil(d.object(forKey: AppServices.legacyExperimentalRecognitionKey))
        AppServices.clearLegacyRecognitionGate(d)
        XCTAssertNil(d.object(forKey: AppServices.legacyExperimentalRecognitionKey))
    }

    func testComingSoonGlyphIsNoneOrValidSymbol() {
        if let s = ResultScreen.comingSoonSymbol { XCTAssertNotNil(UIImage(systemName: s), s) }
        XCTAssertEqual(ResultScreen.comingSoonTitle, "Recognition coming soon")
    }

    @MainActor
    func testDeveloperRowsIncludeSelfTestNotExperimentalToggle() {
        XCTAssertTrue(SettingsView.developerRows.contains(.segnetSelfTest))
        XCTAssertFalse(SettingsView.developerRows.map(\.rawValue).contains("experimentalRecognition"))
        XCTAssertEqual(SettingsView.title(.segnetSelfTest), "SegNet self-test")
    }

    // MARK: - CoreML cache folder

    func testCacheDirCreatedAndExcludedFromBackup() throws {
        let root = tempDir().appendingPathComponent("coreml-cache", isDirectory: true)
        let store = try CoreMLCacheStore.prepare(root: root)
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.root.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
        XCTAssertTrue(CoreMLCacheStore.isExcludedFromBackup(store.root))
        XCTAssertEqual(try CoreMLCacheStore.defaultRoot().pathComponents.suffix(2), ["Application Support", "coreml-cache"])
    }

    func testCacheEntryMarkerAndStaleCleanup() throws {
        let store = try CoreMLCacheStore.prepare(root: tempDir())
        let fm = FileManager.default
        XCTAssertEqual(store.prepareEntry("abc"), .miss)
        try fm.createDirectory(at: store.entry("abc"), withIntermediateDirectories: true)
        XCTAssertEqual(store.prepareEntry("abc"), .incomplete, "folder without marker = half entry")
        XCTAssertFalse(fm.fileExists(atPath: store.entry("abc").path), "half entry deleted")
        try fm.createDirectory(at: store.entry("abc"), withIntermediateDirectories: true)
        store.markComplete("abc")
        XCTAssertEqual(store.prepareEntry("abc"), .hit)
        try fm.createDirectory(at: store.entry("old"), withIntermediateDirectories: true)
        store.markComplete("old")
        XCTAssertEqual(Set(store.removeStale(keeping: ["abc"])), ["old", "old.complete"])
        XCTAssertEqual(store.prepareEntry("abc"), .hit)
    }

    // MARK: - SegNet self-test

    func testSelfTestPageIsBundled() throws {
        let url = try SegNetSelfTest.bundledPage()
        XCTAssertGreaterThan((try Data(contentsOf: url)).count, 1000)
    }

    func testHalfToFloat() {
        XCTAssertEqual(SegNetSelfTest.halfToFloat(0x3C00), 1)
        XCTAssertEqual(SegNetSelfTest.halfToFloat(0xC000), -2)
        XCTAssertEqual(SegNetSelfTest.halfToFloat(0x0001), Float(pow(2.0, -24.0)))
        XCTAssertEqual(SegNetSelfTest.halfToFloat(0x7C00), .infinity)
        XCTAssertTrue(SegNetSelfTest.halfToFloat(0x7E00).isNaN)
    }

    func testPromptHasSegNetSelfTestSection() {
        let log = DiagnosticsLog(directory: nil, mirrorToOSLog: false)
        var cpu = SegNetSelfTest.VariantResult(variant: .cpu)
        cpu.classCounts = SegNetSelfTest.homrClassCounts
        cpu.stats = .init(min: -3, max: 9, nan: 0, inf: 0, count: 10)
        cpu.staffCount = 1
        var nn = SegNetSelfTest.VariantResult(variant: .neuralNetwork)
        nn.unavailable = "unavailable: test"
        SegNetSelfTest.record(.init(page: "p.png 10x10 → 10x10", results: [cpu, nn], totalMs: 5), log: log)
        let device = DeviceInfo(model: "iPhone16,1", os: "iOS 18.0", appVersion: "1.0", build: "6", ortVersion: "1.24.2")
        let text = PromptBuilder.build(.init(device: device, events: log.events))
        XCTAssertTrue(text.contains("## SegNet self-test (latest)\n- SegNet self-test"), text)
        XCTAssertTrue(text.contains("- neuralnetwork: unavailable: test"), text)
        XCTAssertTrue(text.contains("- cpu: classes [5197875, 1240, 2056, 1373, 10256, 0] · L1 vs homr 0"), text)
        let empty = PromptBuilder.build(.init(device: device, events: []))
        XCTAssertTrue(empty.contains("## SegNet self-test (latest)\n- not run"), empty)
    }

    /// Real models (ios-sim): all three variants on the bundled page, off the main thread. CPU must find the
    /// staff; the CoreML rows are reported (grep "SegNetSelfTest" in the CI log), not asserted.
    func testSegNetSelfTestOnBundledPage() async throws {
        do {
            _ = try ModelWarmup.modelFile("segnet_", in: ModelWarmup.resolveModelsDir(nil))
        } catch {
            throw XCTSkip("pinned models not available (\(error))")
        }
        let log = DiagnosticsLog(directory: nil, mirrorToOSLog: false)
        let report = await Task.detached(priority: .userInitiated) { SegNetSelfTest.run(log: log) }.value
        print("SegNetSelfTest: page \(report.page) total \(String(format: "%.0f", report.totalMs)) ms error \(report.error ?? "-")")
        for r in report.results { print("SegNetSelfTest: \(r.variant.rawValue): \(r.line)") }
        XCTAssertNil(report.error)
        XCTAssertEqual(report.results.map(\.variant), SegNetSelfTest.Variant.allCases)
        let cpu = try XCTUnwrap(report.results.first { $0.variant == .cpu })
        XCTAssertEqual(cpu.staffCount, 1, cpu.line)
        XCTAssertEqual(cpu.stats.nan, 0)
        XCTAssertEqual(log.events.last?.payload?["kind"], "segnet_selftest")
    }
}
