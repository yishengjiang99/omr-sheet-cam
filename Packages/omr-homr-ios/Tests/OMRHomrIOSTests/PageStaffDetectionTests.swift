// SPDX-License-Identifier: AGPL-3.0-or-later
//
// omr-sheet-cam — page staff detection (milestone 2) vs fixtures/oracle.pages stages.json.
// Port of liebharc/homr @ 7d97c3cee4ad772b50266fdf9dc78bbf9064701e (AGPL-3.0): checks the Swift port of
// homr/staff_detection.py + brace_dot_detection.py against homr's own intermediate outputs.
import Foundation
import XCTest
@testable import OMRHomrIOS

final class PageStaffDetectionTests: XCTestCase {
    private struct Stages: Decodable {
        struct Geometry: Decodable { var grid: [StaffGeometry.Point]; var regions: [[Double]] }
        struct Input: Decodable { var geometry: Geometry; var is_grandstaff: Bool }
        var average_note_head_height: Double
        var ensured_rows: [Int]
        var staff_inputs: [Input]
        struct Symbols: Decodable { var noteheads: [[Double]] }
        var symbols: Symbols
    }

    private func check(_ fid: String, staffs: Int, grandstaff: Bool) throws {
        let dir = try WriterOnlyFixtureTests.fixturesRoot().appendingPathComponent("oracle.pages/\(fid)")
        let seg = try PagePipeline.decodeGrayPNG(Data(contentsOf: dir.appendingPathComponent("segnet.png")))
        let ref = try JSONDecoder().decode(Stages.self, from: Data(contentsOf: dir.appendingPathComponent("stages.json")))
        let got = try PagePipeline.detectStaffs(segmentation: seg.pixels, width: seg.width, height: seg.height)

        XCTAssertEqual(got.averageNoteHeadHeight, ref.average_note_head_height)
        XCTAssertEqual(got.ensuredRows, ref.ensured_rows)
        XCTAssertEqual(got.symbols["noteheads"], ref.symbols.noteheads)
        XCTAssertEqual(got.staffs.count, staffs)
        XCTAssertEqual(got.staffs.count, ref.staff_inputs.count)
        for (g, r) in zip(got.staffs, ref.staff_inputs) {
            XCTAssertEqual(g.isGrandstaff, r.is_grandstaff)
            XCTAssertEqual(g.isGrandstaff, grandstaff)
            XCTAssertEqual(g.geometry.regions, r.geometry.regions)
            XCTAssertEqual(g.geometry.grid.count, r.geometry.grid.count)
            for (a, b) in zip(g.geometry.grid, r.geometry.grid) {
                XCTAssertEqual(a.x, b.x)
                XCTAssertEqual(a.y, b.y)
            }
        }
    }

    // One page only: the debug build takes ~20 s per page. All 9 pages are checked (release) by
    // `omr-test detect-staffs fixtures/oracle.pages/<id>`.
    /// Grand staff merging (brace detection) + > 127 contour labels in cv2 tree mode (Int8 nbd wrap).
    func testPianoGrandStaff() throws {
        try check("piano.grand", staffs: 1, grandstaff: true)
    }
}
