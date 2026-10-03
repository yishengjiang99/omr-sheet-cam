import CoreGraphics
import Foundation
import UIKit

/// Why a page scan failed, in user terms, derived from `RecognitionOutcome.failed`'s message
/// (`PageStaffDetectionError`, `PageRecognitionService.outcome(for:ms:)`, `Gray8Image.DecodeError`,
/// model loading). The raw message stays available under "Details".
enum ScanFailure: Equatable, Sendable {
    /// SegNet found no noteheads at all (not sheet music, or far too small / blurry / dark).
    case noMusicFound
    /// Notes-like marks but no five-line staff could be traced.
    case noStaffFound
    /// Staffs found, the decoder produced no sounding notes.
    case noNotesFound(staffCount: Int?)
    /// The photo itself could not be decoded.
    case unreadableImage
    /// Models missing / failed to load (not the user's photo).
    case readerUnavailable
    case other

    static func classify(_ message: String) -> ScanFailure {
        let m = message.lowercased()
        if m.contains("no noteheads") { return .noMusicFound }
        if m.contains("no staffs found") || m.contains("no music staff") || m.contains("staffcount 0") { return .noStaffFound }
        if m.contains("no notes recognized") || m.contains("no sounding notes") {
            return .noNotesFound(staffCount: Self.firstInt(in: m, after: "("))
        }
        if m.contains("not decodable") || m.contains("zero width or height") || m.contains("devicegray context") {
            return .unreadableImage
        }
        if m.contains("model") || m.contains("onnx") || m.contains("session") || m.contains("ort") && m.contains("runtime") {
            return .readerUnavailable
        }
        return .other
    }

    var title: String {
        switch self {
        case .noMusicFound: return "No printed notes found"
        case .noStaffFound: return "No music staff found"
        case .noNotesFound: return "Staff found, but no notes"
        case .unreadableImage: return "This photo couldn't be opened"
        case .readerUnavailable: return "The music reader isn't ready"
        case .other: return "Couldn't read this page"
        }
    }

    var explanation: String {
        switch self {
        case .noMusicFound:
            return "We couldn't find any notes in this photo. It works with printed sheet music, one page at a time."
        case .noStaffFound:
            return "We saw note-like marks but couldn't trace the five staff lines, usually because the page is cut off, tilted, curved or in shadow."
        case let .noNotesFound(n):
            let staves = n.map { "\($0) staff\($0 == 1 ? "" : "s")" } ?? "the staff lines"
            return "We found \(staves) but couldn't read any notes on them. The notes may be too small or blurry."
        case .unreadableImage:
            return "The image file couldn't be decoded. Take a new photo or pick a different one."
        case .readerUnavailable:
            return "The on-device music reader didn't start. Wait a moment and try again; restarting the app helps if it keeps happening."
        case .other:
            return "Something went wrong while reading the music."
        }
    }

    /// Whether retaking / re-framing the photo is the fix (vs. retrying the same photo).
    var isPhotoProblem: Bool { self != .readerUnavailable }

    struct Tip: Equatable, Identifiable, Sendable {
        var symbol: String
        var text: String
        var id: String { text }

        static let fitPage = Tip(symbol: "viewfinder", text: "Fit the whole page in the frame with a little margin around it.")
        static let flat = Tip(symbol: "rectangle.portrait", text: "Lay the page flat and hold the phone straight above it, not at an angle.")
        static let light = Tip(symbol: "lightbulb", text: "Use bright, even light. Avoid shadows from your hand or phone, and glare on glossy paper.")
        static let steady = Tip(symbol: "hand.raised", text: "Hold still and tap the page to focus so the notes are sharp.")
        static let closer = Tip(symbol: "plus.magnifyingglass", text: "Move closer: one page at a time, filling most of the frame.")
        static let printed = Tip(symbol: "printer", text: "Printed sheet music works best. Handwritten music may not read.")
        static let dark = Tip(symbol: "flashlight.on.fill", text: "This photo looks dark. Turn on more light or the torch.")
        static let washedOut = Tip(symbol: "sun.max", text: "This photo looks washed out. Avoid glare and direct light on the page.")
        static let small = Tip(symbol: "arrow.up.left.and.arrow.down.right", text: "This photo is small. Use the camera or a larger image.")
    }

    /// Framing / lighting tips for this failure; photo-specific ones (dark, washed out, small) first.
    func tips(quality: PhotoQuality? = nil) -> [Tip] {
        var out: [Tip] = []
        if isPhotoProblem, let q = quality {
            if q.isDark { out.append(.dark) }
            if q.isLowContrast && !q.isDark { out.append(.washedOut) }
            if q.isSmall { out.append(.small) }
        }
        switch self {
        case .noMusicFound: out += [.printed, .fitPage, .steady, .light]
        case .noStaffFound: out += [.fitPage, .flat, .light, .steady]
        case .noNotesFound: out += [.closer, .steady, .light, .flat]
        case .unreadableImage: break
        case .readerUnavailable: break
        case .other: out += [.fitPage, .flat, .light, .steady]
        }
        var seen = Set<String>()
        return out.filter { seen.insert($0.text).inserted }
    }

    private static func firstInt(in s: String, after marker: String) -> Int? {
        guard let r = s.range(of: marker) else { return nil }
        let digits = s[r.upperBound...].prefix { $0.isNumber }
        return Int(digits)
    }
}

/// Cheap photo statistics for failure tips: mean and spread of luma on a 64×64 thumbnail, and size.
struct PhotoQuality: Equatable, Sendable {
    var meanLuma: Double // 0...255
    var lumaStdDev: Double
    var pixelWidth: Int
    var pixelHeight: Int

    var isDark: Bool { meanLuma < 80 }
    var isLowContrast: Bool { lumaStdDev < 22 }
    var isSmall: Bool { max(pixelWidth, pixelHeight) < 1000 }

    static func measure(_ image: UIImage) -> PhotoQuality? {
        guard let cg = image.cgImage ?? CaptureStore.normalizedUpright(image).cgImage else { return nil }
        let n = 64
        var buf = [UInt8](repeating: 0, count: n * n)
        let ok = buf.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
            return true
        }
        guard ok else { return nil }
        return PhotoQuality(luma: buf, width: cg.width, height: cg.height)
    }

    init(meanLuma: Double, lumaStdDev: Double, pixelWidth: Int, pixelHeight: Int) {
        self.meanLuma = meanLuma; self.lumaStdDev = lumaStdDev; self.pixelWidth = pixelWidth; self.pixelHeight = pixelHeight
    }

    init(luma: [UInt8], width: Int, height: Int) {
        let c = Double(max(1, luma.count))
        let mean = luma.reduce(0.0) { $0 + Double($1) } / c
        let v = luma.reduce(0.0) { $0 + (Double($1) - mean) * (Double($1) - mean) } / c
        self.init(meanLuma: mean, lumaStdDev: v.squareRoot(), pixelWidth: width, pixelHeight: height)
    }
}
