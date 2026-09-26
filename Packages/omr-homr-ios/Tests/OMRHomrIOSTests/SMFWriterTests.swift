import XCTest
@testable import OMRHomrIOS

final class SMFWriterTests: XCTestCase {
    func testEmptyFileIsFormat1_480TPQ_TwoTracks() {
        let data = SMFWriter().writeEmpty()
        let header = SMFHeaderInspector.readHeader(from: data)
        XCTAssertNotNil(header)
        XCTAssertEqual(header?.format, 1)
        XCTAssertEqual(header?.trackCount, 2)
        XCTAssertEqual(header?.division, 480)
        XCTAssertEqual(SMFHeaderInspector.trackChunkCount(in: data), 2)
        XCTAssertEqual(String(data: data[0..<4], encoding: .ascii), "MThd")
    }

    func testSingleNoteWritesNoteTrack() {
        let notes = [
            SMFWriter.NoteEvent(midiNote: 60, onsetTicks: 0, durationTicks: 480),
            SMFWriter.NoteEvent(midiNote: 62, onsetTicks: 480, durationTicks: 480),
        ]
        let data = SMFWriter().write(notes: notes)
        let header = SMFHeaderInspector.readHeader(from: data)!
        XCTAssertEqual(header.format, 1)
        XCTAssertEqual(header.division, 480)
        XCTAssertGreaterThan(data.count, 30)
    }

    func testVLQEncoding() {
        XCTAssertEqual(SMFWriter.encodeVLQ(0), [0x00])
        XCTAssertEqual(SMFWriter.encodeVLQ(0x7F), [0x7F])
        XCTAssertEqual(SMFWriter.encodeVLQ(0x80), [0x81, 0x00])
        XCTAssertEqual(SMFWriter.encodeVLQ(480), [0x83, 0x60])
    }
}
