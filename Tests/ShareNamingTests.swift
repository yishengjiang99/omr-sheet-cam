import XCTest
@testable import OMRSheetCam

/// F7.7: sharing from Result must produce `<Title>.mid` like Library/Player (MIDIExport), not the
/// capture-timestamp file name of the playlist file.
final class ShareNamingTests: XCTestCase {
    /// Source lint (the ShareLink lives in a SwiftUI body that unit tests can't drive): Result must not
    /// hand `ShareLink` the raw playlist file URL, whose name is the capture timestamp.
    func testResultScreenDoesNotShareRawPlaylistFileURL() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let src = try String(contentsOf: repo.appendingPathComponent("Sources/App/Capture/ResultScreen.swift"), encoding: .utf8)
        XCTAssertFalse(src.contains("ShareLink(item: url)"), "Result shares the timestamp-named playlist file; use MIDIExport (title-named)")
    }

    @MainActor
    func testResultShareItemIsNamedAfterTheEditedTitle() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("share-naming-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PlaylistStore(directory: dir, samples: [], log: DiagnosticsLog(directory: nil, mirrorToOSLog: false))
        let midi = try SampleMIDI.cMajorScale()
        let scan = try store.addScan(midi: midi, captureName: "20261017-093012-123.jpg")
        XCTAssertEqual(scan.fileName, "20261017-093012-123.mid")
        let renamed = try store.rename(scan, to: "Etude")

        let item = try XCTUnwrap(ResultScreen.shareItem(for: renamed, store: store))
        let url = try item.writeTemporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        XCTAssertEqual(url.lastPathComponent, "Etude.mid")
        XCTAssertEqual(try Data(contentsOf: url), midi)
        XCTAssertNil(ResultScreen.shareItem(for: nil, store: store))
    }
}
