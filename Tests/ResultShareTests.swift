import SF2Player
import XCTest
@testable import OMRSheetCam

/// F7.7: Share from the Result screen produces `<Title>.mid` (like Library / Player), not the
/// capture-timestamp file name of the playlist file.
final class ResultShareTests: XCTestCase {
    private let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("result-share-tests-\(UUID().uuidString)", isDirectory: true)

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    @MainActor
    func testResultShareUsesEditedTitleNotCaptureTimestamp() throws {
        let store = PlaylistStore(directory: dir, log: DiagnosticsLog(directory: nil, mirrorToOSLog: false))
        let midi = try SampleMIDI.cMajorScale()
        let added = try store.addScan(midi: midi, captureName: "20261017-093012-123.jpg")
        XCTAssertEqual(added.fileName, "20261017-093012-123.mid", "precondition: the playlist file is named after the capture")
        let entry = try store.rename(added, to: "Etude: no/1")

        let export = try XCTUnwrap(ResultScreen.shareItem(for: entry, store: store))
        XCTAssertEqual(export.title, "Etude: no/1")
        let url = try export.writeTemporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        XCTAssertEqual(url.lastPathComponent, "Etude- no-1.mid")
        XCTAssertEqual(try Data(contentsOf: url), midi)
    }
}
