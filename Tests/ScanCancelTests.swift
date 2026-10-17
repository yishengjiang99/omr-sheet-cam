import UIKit
import XCTest
@testable import OMRSheetCam

/// F6.8: Cancel on the Reading screen discards the recognition result (no late Library entry / quota
/// charge) and removes the capture JPEG that was saved before recognition.
final class ScanCancelTests: XCTestCase {
    /// Like the real parse, it cannot be aborted: it always finishes after `delay` with a result.
    private struct SlowService: RecognitionService {
        let delay: UInt64
        let outcome: RecognitionOutcome
        func recognize(imageData: Data) async -> RecognitionOutcome {
            await Task.detached { try? await Task.sleep(nanoseconds: delay) }.value // not cancellable via the caller
            return outcome
        }
    }

    private static func recognized() -> RecognitionOutcome {
        .recognized(RecognitionDetails(midi: Data("MThd".utf8), notes: [], staffCount: 1, warnings: [], layoutSource: "midiFallback", ms: 1))
    }

    func testCancelledRecognitionIsDiscardedEvenIfParseFinishesLater() async {
        let service = SlowService(delay: 200_000_000, outcome: Self.recognized())
        let task = Task { await ResultScreen.recognizeUnlessCancelled(service: service, imageData: Data(), progress: { _ in }) }
        try? await Task.sleep(nanoseconds: 30_000_000)
        task.cancel()
        let result = await task.value
        XCTAssertNil(result, "a result produced after Cancel must be dropped (no outcome, save or quota commit)")
    }

    func testUncancelledRecognitionIsReturned() async {
        let service = SlowService(delay: 10_000_000, outcome: Self.recognized())
        let result = await ResultScreen.recognizeUnlessCancelled(service: service, imageData: Data(), progress: { _ in })
        XCTAssertEqual(result?.name, "recognized")
    }

    func testDiscardRemovesOrphanCaptureJPEG() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cancel-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let url = try CaptureStore.save(image, directory: dir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        CaptureStore.discard(url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "cancelled scan must not leave its capture behind")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), [])
        CaptureStore.discard(url) // already gone: no crash
        CaptureStore.discard(nil)
    }
}
