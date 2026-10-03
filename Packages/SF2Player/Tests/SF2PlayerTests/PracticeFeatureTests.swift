// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import XCTest
@testable import SF2Player

/// Player practice features (not in gbk): transpose.
final class PracticeFeatureTests: XCTestCase {
    func testTransposedClampsAndSkipsDrums() {
        XCTAssertEqual(SF2SequenceBuilder.transposed(60, by: 12, channel: 0), 72)
        XCTAssertEqual(SF2SequenceBuilder.transposed(60, by: -12, channel: 3), 48)
        XCTAssertEqual(SF2SequenceBuilder.transposed(120, by: 12, channel: 0), 127)
        XCTAssertEqual(SF2SequenceBuilder.transposed(5, by: -12, channel: 0), 0)
        XCTAssertEqual(SF2SequenceBuilder.transposed(36, by: 5, channel: 9), 36, "GM drums keep their keys")
    }

    func testPlanTransposeShiftsNoteOnAndOff() throws {
        let sf = try SharedSoundFont.get()
        let song = try SMFSong(data: Data(contentsOf: TestPaths.fixtures.appendingPathComponent("c_scale.mid")))
        let base = try SF2SequenceBuilder.plan(song: song, soundFont: sf, sampleRate: 44100)
        let up = try SF2SequenceBuilder.plan(song: song, soundFont: sf, sampleRate: 44100, transpose: 12)
        XCTAssertEqual(base.events.count, up.events.count)
        for (a, b) in zip(base.events, up.events) {
            XCTAssertEqual(a.kind, b.kind)
            XCTAssertEqual(a.frame, b.frame)
            if a.kind == .noteOn || a.kind == .noteOff { XCTAssertEqual(b.note, a.note + 12) } else { XCTAssertEqual(b.note, a.note) }
        }
        XCTAssertEqual(try SF2SequenceBuilder.plan(song: song, soundFont: sf, sampleRate: 44100, transpose: 0).events.map(\.note),
                       base.events.map(\.note))
    }
}
