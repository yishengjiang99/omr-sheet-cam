import SF2Player
import XCTest
@testable import OMRSheetCam

/// Playlist store: save, index reload, delete, bundled samples always present.
final class PlaylistStoreTests: XCTestCase {
    private var dir: URL = FileManager.default.temporaryDirectory
        .appendingPathComponent("playlist-tests-\(UUID().uuidString)", isDirectory: true)
    private let log = DiagnosticsLog(directory: nil, mirrorToOSLog: false)

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    @MainActor
    private func makeStore() -> PlaylistStore { PlaylistStore(directory: dir, log: log) }
    private func scanMIDI() throws -> Data { try SampleMIDI.cMajorScale() }

    @MainActor
    func testBundledSamplesAlwaysPresentAndPlayable() throws {
        let store = makeStore()
        XCTAssertEqual(store.samples.map(\.id), ["sample:sweden", "sample:c-major-scale"])
        XCTAssertTrue(store.scans.isEmpty)
        for s in store.samples {
            XCTAssertEqual(s.source, .sample)
            XCTAssertFalse(s.isDeletable)
            XCTAssertGreaterThan(s.duration, 0, s.title)
            XCTAssertNoThrow(try SMFSong(data: store.midiData(for: s)), s.title)
        }
        XCTAssertEqual(store.samples[0].duration, 83.478272, accuracy: 1e-6)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.indexURL.path), "samples are never written to the index")
    }

    @MainActor
    func testAddScanWritesMIDIAndIndexAndAppends() throws {
        let store = makeStore()
        let midi = try scanMIDI()
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let e = try store.addScan(midi: midi, captureName: "20260926-134501-123.jpg", date: date)
        XCTAssertEqual(e.fileName, "20260926-134501-123.mid")
        XCTAssertEqual(e.source, .scan)
        XCTAssertEqual(e.captureName, "20260926-134501-123.jpg")
        XCTAssertTrue(e.title.hasPrefix("Scan "))
        XCTAssertEqual(e.duration, try SMFSong(data: midi).durationSec, accuracy: 1e-9)
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("20260926-134501-123.mid")), midi)
        XCTAssertEqual(try store.midiData(for: e), midi)
        XCTAssertEqual(store.entries.map(\.id), ["20260926-134501-123.mid", "sample:sweden", "sample:c-major-scale"])

        // Same capture name again → unique file; appended after the first.
        let e2 = try store.addScan(midi: midi, captureName: "20260926-134501-123.jpg", date: date.addingTimeInterval(60))
        XCTAssertEqual(e2.fileName, "20260926-134501-123-2.mid")
        XCTAssertEqual(store.scans.map(\.id), [e.id, e2.id])
        // No capture name → timestamp file name.
        let e3 = try store.addScan(midi: midi, captureName: nil, date: date)
        XCTAssertEqual(e3.fileName, "\(CaptureStore.timestamp(date)).mid")

        let index = try JSONSerialization.jsonObject(with: Data(contentsOf: store.indexURL)) as? [[String: Any]]
        XCTAssertEqual(index?.count, 3)
        XCTAssertEqual(index?.first?["source"] as? String, "scan")
        XCTAssertNotNil(index?.first?["duration"] as? Double)
        XCTAssertNotNil(index?.first?["date"] as? String)
        XCTAssertNotNil(index?.first?["title"] as? String)
    }

    @MainActor
    func testIndexReloadsInANewStore() throws {
        let midi = try scanMIDI()
        let a = makeStore()
        let e1 = try a.addScan(midi: midi, title: "First", captureName: "a.jpg", date: Date(timeIntervalSince1970: 1000))
        let e2 = try a.addScan(midi: midi, title: "Second", captureName: "b.jpg", date: Date(timeIntervalSince1970: 2000))

        let b = makeStore()
        XCTAssertEqual(b.scans, [e1, e2])
        XCTAssertEqual(b.scans.map(\.title), ["First", "Second"])
        XCTAssertEqual(b.scans[0].date, Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(b.samples.count, 2)
        XCTAssertEqual(try b.midiData(for: b.scans[1]), midi)
    }

    @MainActor
    func testDeleteRemovesFileAndIndexEntryButNotSamples() throws {
        let store = makeStore()
        let midi = try scanMIDI()
        let keep = try store.addScan(midi: midi, captureName: "keep.jpg")
        let gone = try store.addScan(midi: midi, captureName: "gone.jpg")
        try store.delete(gone)
        XCTAssertEqual(store.scans, [keep])
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("gone.mid").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("keep.mid").path))
        XCTAssertEqual(makeStore().scans, [keep], "delete persisted to index.json")

        XCTAssertThrowsError(try store.delete(store.samples[0])) { err in
            guard case PlaylistStore.StoreError.notDeletable = err else { return XCTFail("\(err)") }
        }
        XCTAssertEqual(store.samples.count, 2)
        XCTAssertThrowsError(try store.delete(gone))

        try store.delete(keep)
        XCTAssertTrue(store.scans.isEmpty)
        XCTAssertEqual(store.entries.map(\.source), [.sample, .sample], "samples survive deleting every scan")
    }

    @MainActor
    func testReloadToleratesMissingFilesAndCorruptIndex() throws {
        let store = makeStore()
        let midi = try scanMIDI()
        let a = try store.addScan(midi: midi, captureName: "a.jpg")
        _ = try store.addScan(midi: midi, captureName: "b.jpg")
        try FileManager.default.removeItem(at: dir.appendingPathComponent("b.mid"))
        XCTAssertEqual(makeStore().scans, [a])

        try Data("not json".utf8).write(to: store.indexURL)
        let c = makeStore()
        XCTAssertTrue(c.scans.isEmpty)
        XCTAssertEqual(c.samples.count, 2)
        // A corrupt index is replaced on the next save.
        let d = try c.addScan(midi: midi, captureName: "d.jpg")
        XCTAssertEqual(makeStore().scans, [d])
    }

    @MainActor
    func testAddScanRejectsInvalidMIDI() throws {
        let store = makeStore()
        XCTAssertThrowsError(try store.addScan(midi: Data("nope".utf8), captureName: "x.jpg"))
        XCTAssertTrue(store.scans.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("x.mid").path))
    }

    @MainActor
    func testNeighborsFollowScansNewestFirstThenSamples() throws {
        let store = makeStore()
        let a = try store.addScan(midi: try scanMIDI(), captureName: "a.jpg")
        let b = try store.addScan(midi: try scanMIDI(), captureName: "b.jpg")
        XCTAssertEqual(store.entries.map(\.id), [b.id, a.id, "sample:sweden", "sample:c-major-scale"])
        XCTAssertNil(store.neighbor(of: b.id, offset: -1))
        XCTAssertEqual(store.neighbor(of: b.id, offset: 1)?.id, a.id)
        XCTAssertEqual(store.neighbor(of: a.id, offset: 1)?.id, "sample:sweden")
        XCTAssertNil(store.neighbor(of: "sample:c-major-scale", offset: 1))
        XCTAssertNil(store.neighbor(of: "missing", offset: 1))
        let old = try store.addScan(midi: try scanMIDI(), captureName: "old.jpg", date: Date(timeIntervalSinceNow: -86400))
        XCTAssertEqual(store.entries.first?.id, b.id, "ordered by date, not insertion")
        XCTAssertEqual(store.entries[2].id, old.id)
    }

    @MainActor
    func testRenameAndSearch() throws {
        let store = makeStore()
        let a = try store.addScan(midi: try scanMIDI(), captureName: "a.jpg")
        let renamed = try store.rename(a, to: "  Minuet in G  ")
        XCTAssertEqual(renamed.title, "Minuet in G")
        XCTAssertEqual(renamed.fileName, a.fileName, "rename edits index.json only; the file keeps its name")
        XCTAssertEqual(makeStore().scans.first?.title, "Minuet in G", "rename persisted")
        XCTAssertEqual(try store.rename(store.samples[0], to: "x").title, "Sweden (sample)", "samples keep their title")
        XCTAssertEqual(store.search("minuet").map(\.id), [a.id])
        XCTAssertEqual(store.search("SWEDEN").map(\.id), ["sample:sweden"])
        XCTAssertEqual(store.search(" ").count, 3)
    }

    @MainActor
    func testFileNamesAreSanitized() {
        XCTAssertEqual(PlaylistStore.sanitized("a b/c:d"), "a_b_c_d")
        XCTAssertEqual(PlaylistStore.sanitized(""), "scan")
    }
}
