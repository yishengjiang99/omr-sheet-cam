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
}
