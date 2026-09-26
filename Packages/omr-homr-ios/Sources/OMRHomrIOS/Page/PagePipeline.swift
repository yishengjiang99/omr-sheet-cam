// SPDX-License-Identifier: AGPL-3.0-or-later
// Port of liebharc/homr @ 7d97c3cee4ad772b50266fdf9dc78bbf9064701e (AGPL-3.0):
//   homr/main.py  load_and_preprocess_predictions / detect_staffs_in_image (page-level pipeline stages)
// Public stage API of the page pipeline (page -> preprocessing -> SegNet -> ...), used by
// `OMRHomrIOS.parseSheetMusicWithLayout` and by `omr-test segnet-page` for oracle comparisons.

import Foundation

public enum PagePipeline {
    /// Same limits as the PNG path (`OMRPNG.PNGDecoder.maxSide` / `.maxPixels`).
    public static let maxSide = 1 << 16
    public static let maxPixels = 1 << 27

    public struct Rect: Equatable, Sendable, Codable {
        public var x: Int
        public var y: Int
        public var width: Int
        public var height: Int
    }

    /// homr's page preprocessing output: `autocrop` -> `resize_image` (1920 wide) -> `apply_clahe`.
    public struct PreprocessedPage: Sendable {
        /// `autocrop` rect in input pixels (the full image when homr keeps the page as is).
        public var crop: Rect
        public var cropped: Bool
        public var width: Int
        public var height: Int
        /// Resized page (gray), `width * height`.
        public var resized: [UInt8]
        /// CLAHE output (SegNet input and the page staffs are cut from), `width * height`.
        public var preprocessed: [UInt8]
    }

    /// Validate a raw gray8 page: positive size, `count == width * height`, PNG-path size limits.
    public static func validate(byteCount: Int, width: Int, height: Int) throws {
        guard width > 0, height > 0 else {
            throw OMRError.invalidPixelBuffer("width and height must be positive, got \(width)x\(height)")
        }
        guard width <= maxSide, height <= maxSide else {
            throw OMRError.invalidPixelBuffer("\(width)x\(height) exceeds the maximum side of \(maxSide) px")
        }
        let (px, overflow) = width.multipliedReportingOverflow(by: height)
        guard !overflow, px <= maxPixels else {
            throw OMRError.invalidPixelBuffer("\(width)x\(height) exceeds the maximum of \(maxPixels) pixels")
        }
        guard byteCount == px else {
            throw OMRError.invalidPixelBuffer(
                "gray8.count is \(byteCount) bytes but width*height = \(width)*\(height) = \(px); expected one "
                + "8-bit gray byte per pixel, row-major, no row padding")
        }
    }

    /// Raw 8-bit gray page (row-major, no padding, upright) -> homr preprocessing. Reads `gray8` in place
    /// (no copy); the largest allocation at input resolution is autocrop's binary mask ((w+2)*(h+2) bytes),
    /// released before the page is resized to 1920 wide.
    public static func preprocess(gray8: Data, width: Int, height: Int) throws -> PreprocessedPage {
        try validate(byteCount: gray8.count, width: width, height: height)
        let out = gray8.withUnsafeBytes { raw -> PagePreprocess.Output in
            let p = raw.bindMemory(to: UInt8.self)
            return PagePreprocess.run(GrayPlane(base: p.baseAddress!, width: width, height: height, stride: width))
        }
        return PreprocessedPage(
            crop: Rect(x: out.crop.x, y: out.crop.y, width: out.crop.width, height: out.crop.height),
            cropped: out.cropped, width: out.width, height: out.height,
            resized: out.resized, preprocessed: out.preprocessed)
    }

    /// PNG page (decoded like homr's `cv2.imread` + BGR2GRAY) -> `preprocess(gray8:width:height:)`.
    public static func preprocess(pngURL: URL) throws -> PreprocessedPage {
        let g = try StaffTensor.decodeGrayPNG(StaffTensor.readPNG(pngURL))
        return try preprocess(gray8: Data(g.pixels), width: g.width, height: g.height)
    }

    /// PNG bytes -> 8-bit gray exactly as homr reads a page (`cv2.imread` + `COLOR_BGR2GRAY`).
    public static func decodeGrayPNG(_ data: Data) throws -> (pixels: [UInt8], width: Int, height: Int) {
        try StaffTensor.decodeGrayPNG(data)
    }

    /// SegNet over the preprocessed page: merged class map (uint8 0..5, `width * height`;
    /// 1 stems_rests, 2 notehead, 3 clefs_keys, 4 staff, 5 symbols).
    public static func segment(_ page: PreprocessedPage, segnet: SegNetSession) throws -> [UInt8] {
        try segnet.segment(preprocessed: page.preprocessed, width: page.width, height: page.height)
    }
}
