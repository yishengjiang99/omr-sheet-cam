import XCTest
@testable import OMRScanKit

final class SMFWriterTests: XCTestCase {
    static let twoParts = Score(parts: [
        ScorePart(name: "Treble", program: nil, notes: [ScoreNote(pitch: 72, onset: 1, duration: 1, velocity: 90),
                                                       ScoreNote(pitch: 60, onset: 0, duration: 0.5, velocity: 200)]),
        ScorePart(name: "Bass", program: 32, notes: [ScoreNote(pitch: 48, onset: 0, duration: 2, velocity: 64)]),
        ScorePart(name: "Empty", program: nil, notes: []),
    ], tempo: 100, key: "G", timeSig: TimeSignature(numerator: 3, denominator: 4))

    func testScoreRoundTripsThroughSMF() throws {
        let score = Self.twoParts
        let back = try SMFReader.score(from: SMFWriter.data(for: score))
        XCTAssertEqual(back.tempo, 100)
        XCTAssertEqual(back.timeSig, TimeSignature(numerator: 3, denominator: 4))
        XCTAssertEqual(back.key, "G")
        XCTAssertEqual(back.parts.count, 2, "empty parts are dropped")
        XCTAssertEqual(back.parts[0].name, "Treble")
        XCTAssertEqual(back.parts[0].notes, [ScoreNote(pitch: 60, onset: 0, duration: 0.5, velocity: 127),
                                             ScoreNote(pitch: 72, onset: 1, duration: 1, velocity: 90)])
        XCTAssertEqual(back.parts[1].program, 32)
        XCTAssertEqual(back.parts[1].notes, [ScoreNote(pitch: 48, onset: 0, duration: 2, velocity: 64)])
    }

    func testRepeatedPitchRetriggersAndChannelsSkipDrums() throws {
        let s = Score(parts: [ScorePart(name: "P", program: nil, notes: [ScoreNote(pitch: 64, onset: 0, duration: 1, velocity: 80),
                                                                         ScoreNote(pitch: 64, onset: 1, duration: 1, velocity: 80)])])
        XCTAssertEqual(try SMFReader.score(from: SMFWriter.data(for: s)).parts[0].notes.count, 2)
        XCTAssertEqual((0..<11).map(SMFWriter.channel(for:)), [0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 11])
        XCTAssertEqual(SMFWriter.vlq(480), [0x83, 0x60])
        XCTAssertEqual(SMFWriter.keySignature("Ebm")?.sharps, -6)
    }

    func testSMFReaderParsesNotesTempoKeyTimeSig() throws {
        func vlq(_ v: Int) -> [UInt8] { v < 128 ? [UInt8(v)] : [UInt8(0x80 | (v >> 7)), UInt8(v & 0x7f)] }
        func trk(_ ev: [UInt8]) -> [UInt8] { let e = ev + [0, 0xff, 0x2f, 0]; return Array("MTrk".utf8) + [0, 0, UInt8(e.count >> 8), UInt8(e.count & 0xff)] + e }
        let conductor = trk([0, 0xff, 0x51, 3, 0x07, 0xa1, 0x20, 0, 0xff, 0x58, 4, 4, 2, 24, 8, 0, 0xff, 0x59, 2, 2, 0])
        let notes = trk([0, 0x90, 60, 100] + vlq(480) + [0x80, 60, 0, 0, 0x90, 64, 90] + vlq(960) + [64, 0])
        let smf = Array("MThd".utf8) + [0, 0, 0, 6, 0, 1, 0, 2, 0x01, 0xe0] + conductor + notes
        let s = try SMFReader.score(from: Data(smf))
        XCTAssertEqual(s.tempo, 120)
        XCTAssertEqual(s.key, "D")
        XCTAssertEqual(s.parts.first?.notes, [ScoreNote(pitch: 60, onset: 0, duration: 1, velocity: 100), ScoreNote(pitch: 64, onset: 1, duration: 2, velocity: 90)])
    }
}
