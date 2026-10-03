import CoreGraphics
import Foundation
import ImageIO
import UIKit

/// Upright 8-bit grayscale page for `PageInferenceSession.parsePage(gray8:width:height:)`:
/// row-major, one byte per pixel, `bytesPerRow == width` (no padding), EXIF orientation applied.
///
/// Rendered through an 8-bit gray `CGContext` whose rows are exactly `width` bytes, so
/// `pixels.count == width * height` always holds. Color sources (camera photos) convert to
/// `DeviceGray`; gray sources (scans, PNG fixtures) render in their own gray color space, so no
/// color conversion happens and bytes match homr's `cv2.imread` + `BGR2GRAY`. Transparent areas
/// composite over white (paper).
struct Gray8Image: Equatable, Sendable {
    var pixels: Data
    var width: Int
    var height: Int
    /// EXIF orientation that was applied (1 = up).
    var orientation: UInt32 = 1
    /// Source pixel format, for diagnostics (e.g. "rgb 8bpc 4032x3024", "gray 8bpc 1654x2339").
    var source: String = ""

    enum DecodeError: Error, Equatable, CustomStringConvertible {
        case undecodable(String)
        case emptyImage
        case contextFailed(Int, Int)

        var description: String {
            switch self {
            case let .undecodable(m): return "image not decodable: \(m)"
            case .emptyImage: return "image has zero width or height"
            case let .contextFailed(w, h): return "could not create a \(w)x\(h) DeviceGray context"
            }
        }
    }

    /// Encoded bytes (JPEG / HEIC / PNG / …) → upright gray8, using the file's EXIF orientation.
    static func decode(imageData: Data) throws -> Gray8Image {
        guard !imageData.isEmpty else { throw DecodeError.undecodable("0 bytes") }
        let opts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithData(imageData as CFData, opts), CGImageSourceGetCount(src) > 0 else {
            throw DecodeError.undecodable("unknown format (\(imageData.count) B)")
        }
        guard let cg = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else {
            throw DecodeError.undecodable("no image at index 0 (\(imageData.count) B)")
        }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let raw = (props?[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
        return try from(cgImage: cg, orientation: CGImagePropertyOrientation(rawValue: raw) ?? .up)
    }

    /// `UIImage` (camera / picker) → upright gray8 using `imageOrientation`.
    static func from(_ image: UIImage) throws -> Gray8Image {
        guard let cg = image.cgImage else {
            // CIImage-backed: render through UIKit first (already upright).
            let up = CaptureStore.normalizedUpright(image)
            guard let cg2 = up.cgImage else { throw DecodeError.undecodable("UIImage has no CGImage") }
            return try from(cgImage: cg2, orientation: .up)
        }
        return try from(cgImage: cg, orientation: CGImagePropertyOrientation(image.imageOrientation))
    }

    /// Raw `CGImage` pixels + EXIF orientation → upright gray8.
    static func from(cgImage cg: CGImage, orientation: CGImagePropertyOrientation) throws -> Gray8Image {
        let rawW = cg.width, rawH = cg.height
        guard rawW > 0, rawH > 0 else { throw DecodeError.emptyImage }
        let swaps: Bool
        switch orientation {
        case .left, .leftMirrored, .right, .rightMirrored: swaps = true
        default: swaps = false
        }
        let w = swaps ? rawH : rawW
        let h = swaps ? rawW : rawH
        let srcSpace = cg.colorSpace
        let isGray = srcSpace?.model == .monochrome
        var pixels = Data(count: w * h)
        let ok = pixels.withUnsafeMutableBytes { buf -> Bool in
            guard let base = buf.baseAddress else { return false }
            func context(_ space: CGColorSpace) -> CGContext? {
                CGContext(data: base, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                          space: space, bitmapInfo: CGImageAlphaInfo.none.rawValue)
            }
            let gray = isGray ? srcSpace.flatMap(context) : nil
            guard let ctx = gray ?? context(CGColorSpaceCreateDeviceGray()), ctx.bytesPerRow == w else { return false }
            ctx.interpolationQuality = .none
            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.concatenate(orientationTransform(orientation, width: CGFloat(w), height: CGFloat(h)))
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: rawW, height: rawH))
            return true
        }
        guard ok else { throw DecodeError.contextFailed(w, h) }
        let model: String
        switch srcSpace?.model {
        case .monochrome?: model = "gray"
        case .rgb?: model = "rgb"
        case .cmyk?: model = "cmyk"
        case nil: model = "mask"
        default: model = "other"
        }
        let opaque: [CGImageAlphaInfo] = [.none, .noneSkipFirst, .noneSkipLast]
        let alpha = opaque.contains(cg.alphaInfo) ? "" : "+alpha"
        let name = (srcSpace?.name as String?).map { " " + ($0 as NSString).lastPathComponent } ?? ""
        return Gray8Image(pixels: pixels, width: w, height: h, orientation: orientation.rawValue,
                          source: "\(model)\(alpha) \(cg.bitsPerComponent)bpc \(rawW)x\(rawH)\(name)")
    }

    /// CTM mapping raw image space (drawn at `(0, 0, rawW, rawH)`) onto the upright `width x height`
    /// canvas (CG coordinates, origin bottom-left).
    static func orientationTransform(_ o: CGImagePropertyOrientation, width W: CGFloat, height H: CGFloat) -> CGAffineTransform {
        var t = CGAffineTransform.identity
        switch o {
        case .down, .downMirrored: t = t.translatedBy(x: W, y: H).rotated(by: .pi)
        case .left, .leftMirrored: t = t.translatedBy(x: W, y: 0).rotated(by: .pi / 2)
        case .right, .rightMirrored: t = t.translatedBy(x: 0, y: H).rotated(by: -.pi / 2)
        default: break
        }
        switch o {
        case .upMirrored, .downMirrored: t = t.translatedBy(x: W, y: 0).scaledBy(x: -1, y: 1)
        case .leftMirrored, .rightMirrored: t = t.translatedBy(x: H, y: 0).scaledBy(x: -1, y: 1)
        default: break
        }
        return t
    }

    /// Pixel at upright `(x, y)` (y down).
    subscript(x: Int, y: Int) -> UInt8 { pixels[pixels.startIndex + y * width + x] }
}

/// Upright color page for `PageInferenceSession.parsePage(rgbx:...)`: 4 bytes per pixel in R, G, B, X
/// order, `bytesPerRow == 4 * width`, EXIF orientation applied. RGB sources render in their own color
/// space (no color management, like homr's `cv2.imread`), others in DeviceRGB; transparency over white.
struct RGBXImage: Equatable, Sendable {
    var pixels: Data
    var width: Int
    var height: Int
    var orientation: UInt32 = 1
    var source: String = ""
    var bytesPerRow: Int { width * 4 }

    /// Upright page as homr would read it: gray sources stay gray8 (byte-identical to the fixture path),
    /// color sources become RGBX so preprocessing can autocrop / resize in color first.
    enum Page: Sendable {
        case gray(Gray8Image)
        case color(RGBXImage)

        var width: Int { switch self { case let .gray(g): return g.width; case let .color(c): return c.width } }
        var height: Int { switch self { case let .gray(g): return g.height; case let .color(c): return c.height } }
        var orientation: UInt32 { switch self { case let .gray(g): return g.orientation; case let .color(c): return c.orientation } }
        var source: String { switch self { case let .gray(g): return g.source; case let .color(c): return c.source } }
        var mode: String { switch self { case .gray: return "gray"; case .color: return "color" } }
    }

    static func decodePage(imageData: Data) throws -> Page {
        guard !imageData.isEmpty else { throw Gray8Image.DecodeError.undecodable("0 bytes") }
        let opts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithData(imageData as CFData, opts), CGImageSourceGetCount(src) > 0 else {
            throw Gray8Image.DecodeError.undecodable("unknown format (\(imageData.count) B)")
        }
        guard let cg = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else {
            throw Gray8Image.DecodeError.undecodable("no image at index 0 (\(imageData.count) B)")
        }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let raw = (props?[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
        let o = CGImagePropertyOrientation(rawValue: raw) ?? .up
        if cg.colorSpace?.model == .monochrome { return .gray(try Gray8Image.from(cgImage: cg, orientation: o)) }
        return .color(try from(cgImage: cg, orientation: o))
    }

    static func from(cgImage cg: CGImage, orientation: CGImagePropertyOrientation) throws -> RGBXImage {
        let rawW = cg.width, rawH = cg.height
        guard rawW > 0, rawH > 0 else { throw Gray8Image.DecodeError.emptyImage }
        let swaps: Bool
        switch orientation {
        case .left, .leftMirrored, .right, .rightMirrored: swaps = true
        default: swaps = false
        }
        let w = swaps ? rawH : rawW
        let h = swaps ? rawW : rawH
        let srcSpace = cg.colorSpace
        let space = (srcSpace?.model == .rgb ? srcSpace : nil) ?? CGColorSpaceCreateDeviceRGB()
        var pixels = Data(count: w * h * 4)
        let ok = pixels.withUnsafeMutableBytes { buf -> Bool in
            guard let base = buf.baseAddress,
                  let ctx = CGContext(data: base, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                  ctx.bytesPerRow == w * 4 else { return false }
            ctx.interpolationQuality = .none
            ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.concatenate(Gray8Image.orientationTransform(orientation, width: CGFloat(w), height: CGFloat(h)))
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: rawW, height: rawH))
            return true
        }
        guard ok else { throw Gray8Image.DecodeError.contextFailed(w, h) }
        let name = (srcSpace?.name as String?).map { " " + ($0 as NSString).lastPathComponent } ?? ""
        return RGBXImage(pixels: pixels, width: w, height: h, orientation: orientation.rawValue,
                         source: "rgb \(cg.bitsPerComponent)bpc \(rawW)x\(rawH)\(name)")
    }

    /// Pixel (r, g, b) at upright `(x, y)` (y down).
    subscript(x: Int, y: Int) -> (UInt8, UInt8, UInt8) {
        let i = pixels.startIndex + (y * width + x) * 4
        return (pixels[i], pixels[i + 1], pixels[i + 2])
    }

    /// OpenCV BGR2GRAY of every pixel (fakes / fallbacks that only take gray8).
    func gray8() -> Data {
        var out = Data(count: width * height)
        pixels.withUnsafeBytes { src in
            out.withUnsafeMutableBytes { dst in
                let s = src.bindMemory(to: UInt8.self), d = dst.bindMemory(to: UInt8.self)
                for i in 0 ..< width * height {
                    let r = Int(s[i * 4]), g = Int(s[i * 4 + 1]), b = Int(s[i * 4 + 2])
                    let sum: Int = r * 9798 + g * 19235 + b * 3735 + 16384
                    d[i] = UInt8(sum >> 15)
                }
            }
        }
        return out
    }
}

extension CGImagePropertyOrientation {
    init(_ o: UIImage.Orientation) {
        switch o {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
