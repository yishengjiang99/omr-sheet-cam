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
        XCTAssertEqual(store.samples.map(\.id), ["sample:ode-to-joy", "sample:c-major-scale"])
        XCTAssertTrue(store.scans.isEmpty)
        for s in store.samples {
            XCTAssertEqual(s.source, .sample)
            XCTAssertFalse(s.isDeletable)
            XCTAssertGreaterThan(s.duration, 0, s.title)
            XCTAssertNoThrow(try SMFSong(data: store.midiData(for: s)), s.title)
        }
        XCTAssertEqual(store.samples[0].duration, 38.4, accuracy: 1e-6)
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
        XCTAssertEqual(store.entries.map(\.id), ["20260926-134501-123.mid", "sample:ode-to-joy", "sample:c-major-scale"])

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

    /// F2.7: deleting a scan must also remove its captured JPEG (Documents/captures/<captureName>),
    /// but must keep a JPEG that another scan still references and must not touch unrelated files.
    @MainActor
    func testDeleteRemovesCaptureJPEGButKeepsSharedAndUnrelatedOnes() throws {
        let caps = try CaptureStore.defaultDirectory()
        try FileManager.default.createDirectory(at: caps, withIntermediateDirectories: true)
        let tag = UUID().uuidString.prefix(8)
        let goneJPG = "f27-gone-\(tag).jpg", sharedJPG = "f27-shared-\(tag).jpg", otherJPG = "f27-other-\(tag).jpg"
        for n in [goneJPG, sharedJPG, otherJPG] { try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: caps.appendingPathComponent(n)) }
        defer { for n in [goneJPG, sharedJPG, otherJPG] { try? FileManager.default.removeItem(at: caps.appendingPathComponent(n)) } }
        func exists(_ n: String) -> Bool { FileManager.default.fileExists(atPath: caps.appendingPathComponent(n).path) }

        let store = makeStore()
        let midi = try scanMIDI()
        let gone = try store.addScan(midi: midi, captureName: goneJPG)
        let s1 = try store.addScan(midi: midi, title: "shared 1", captureName: sharedJPG)
        let s2 = try store.addScan(midi: midi, title: "shared 2", captureName: sharedJPG)
        XCTAssertNotEqual(s1.id, s2.id)

        try store.delete(gone)
        XCTAssertFalse(exists(goneJPG), "capture JPEG must be deleted with its scan")
        XCTAssertTrue(exists(otherJPG), "unrelated captures untouched")

        try store.delete(s1)
        XCTAssertTrue(exists(sharedJPG), "JPEG still referenced by another scan must stay")
        try store.delete(s2)
        XCTAssertFalse(exists(sharedJPG), "last referencing scan removes the JPEG")
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
        // F2.9: a corrupt index no longer empties the Library; scans are rebuilt from the .mid files.
        XCTAssertEqual(c.scans.map(\.id), [a.id])
        XCTAssertEqual(c.samples.count, 2)
        XCTAssertNotNil(c.loadNotice, "an unreadable index must be surfaced, not silent")
        let d = try c.addScan(midi: midi, captureName: "d.jpg")
        XCTAssertEqual(Set(makeStore().scans.map(\.id)), [a.id, d.id], "next save must not drop the recovered scans")
    }

    /// F2.9: unreadable index.json is backed up (never overwritten), the Library is rebuilt from the
    /// saved .mid files, and the rebuilt index is persisted so a relaunch is clean.
    @MainActor
    func testCorruptIndexIsBackedUpAndRebuiltFromMIDIFiles() throws {
        let store = makeStore()
        let midi = try scanMIDI()
        let a = try store.addScan(midi: midi, title: "Alpha", captureName: "alpha.jpg", date: Date(timeIntervalSince1970: 1_000))
        let b = try store.addScan(midi: midi, title: "Beta", captureName: "beta.jpg", date: Date(timeIntervalSince1970: 2_000))
        let garbage = Data("not json {".utf8)
        try garbage.write(to: store.indexURL)

        let recovered = makeStore()
        XCTAssertEqual(Set(recovered.scans.map(\.id)), [a.id, b.id], "scans must be rebuilt from .mid files")
        for e in recovered.scans { XCTAssertEqual(try recovered.midiData(for: e), midi) }
        XCTAssertNotNil(recovered.loadNotice, "an unreadable index must be surfaced to the user")
        recovered.dismissLoadNotice()
        XCTAssertNil(recovered.loadNotice)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        let backups = names.filter { $0.hasPrefix("index.json.corrupt-") }
        XCTAssertEqual(backups.count, 1, "damaged index must be kept as index.json.corrupt-<ts>; dir=\(names)")
        if let backup = backups.first {
            XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent(backup)), garbage)
        }

        let again = makeStore()
        XCTAssertEqual(Set(again.scans.map(\.id)), [a.id, b.id], "rebuilt index persisted")
        XCTAssertNil(again.loadNotice, "healthy relaunch shows no notice")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix("index.json.corrupt-") }.count, 1,
                       "a healthy relaunch must not create another backup")
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
        XCTAssertEqual(store.entries.map(\.id), [b.id, a.id, "sample:ode-to-joy", "sample:c-major-scale"])
        XCTAssertNil(store.neighbor(of: b.id, offset: -1))
        XCTAssertEqual(store.neighbor(of: b.id, offset: 1)?.id, a.id)
        XCTAssertEqual(store.neighbor(of: a.id, offset: 1)?.id, "sample:ode-to-joy")
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
        XCTAssertEqual(try store.rename(store.samples[0], to: "x").title, "Ode to Joy (sample)", "samples keep their title")
        XCTAssertEqual(store.search("minuet").map(\.id), [a.id])
        XCTAssertEqual(store.search("ODE TO").map(\.id), ["sample:ode-to-joy"])
        XCTAssertEqual(store.search(" ").count, 3)
    }

    @MainActor
    func testFileNamesAreSanitized() {
        XCTAssertEqual(PlaylistStore.sanitized("a b/c:d"), "a_b_c_d")
        XCTAssertEqual(PlaylistStore.sanitized(""), "scan")
    }
}
