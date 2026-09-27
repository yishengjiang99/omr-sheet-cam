import Foundation
import UIKit

/// Pure helpers for captured / picked images (unit-tested; no camera hardware).
enum CaptureStore {
    /// Redraws `image` so its pixels are upright and `imageOrientation == .up` (EXIF baked in).
    static func normalizedUpright(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    /// `<Documents>/captures`.
    static func defaultDirectory() throws -> URL {
        try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("captures", isDirectory: true)
    }

    /// `yyyyMMdd-HHmmss-SSS` in the device time zone.
    static func timestamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return f.string(from: date)
    }

    enum SaveError: Error, CustomStringConvertible {
        case encodeFailed
        var description: String { "could not JPEG-encode the image" }
    }

    /// Saves an upright JPEG to `<directory>/<timestamp>.jpg` (default Documents/captures).
    @discardableResult
    static func save(
        _ image: UIImage, date: Date = Date(), directory: URL? = nil, quality: CGFloat = 0.9
    ) throws -> URL {
        let dir = try directory ?? defaultDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = normalizedUpright(image).jpegData(compressionQuality: quality) else {
            throw SaveError.encodeFailed
        }
        var url = dir.appendingPathComponent("\(timestamp(date)).jpg")
        var n = 1
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("\(timestamp(date))-\(n).jpg")
            n += 1
        }
        try data.write(to: url, options: .atomic)
        return url
    }
}

/// A captured or picked photo, already upright. Identity-based so it can be a navigation value.
struct CapturedPhoto: Hashable, Identifiable {
    enum Source: String { case camera, library, sample }
    let id = UUID()
    let image: UIImage
    let source: Source

    static func == (a: CapturedPhoto, b: CapturedPhoto) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

/// "Try sample picture": the bundled photo of the Sweden piano sheet music
/// (`fixtures/samples/sweden.jpg`, bundled at the app root as `sweden.jpg`). Loaded exactly like a
/// Photos pick (decode + `normalizedUpright`) and handed to the same `onPhoto` → `ResultScreen`
/// recognition flow, so the result lands in the Library like any other scan.
enum SamplePicture {
    static let buttonTitle = "Try sample picture"
    static let resourceName = "sweden"
    static let resourceExtension = "jpg"

    enum LoadError: Error, CustomStringConvertible {
        case missing, unreadable
        var description: String {
            switch self {
            case .missing: return "sample picture sweden.jpg is not bundled"
            case .unreadable: return "sample picture sweden.jpg could not be decoded"
            }
        }
    }

    /// Encoded JPEG bytes of the bundled sample picture.
    static func data(bundle: Bundle = .main) throws -> Data {
        guard let url = bundle.url(forResource: resourceName, withExtension: resourceExtension) else {
            throw LoadError.missing
        }
        return try Data(contentsOf: url)
    }

    /// The sample as an upright `CapturedPhoto` (decoded off the main thread, like a Photos pick).
    static func photo(bundle: Bundle = .main) async throws -> CapturedPhoto {
        let data = try data(bundle: bundle)
        let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            UIImage(data: data).map(CaptureStore.normalizedUpright)
        }.value
        guard let image else { throw LoadError.unreadable }
        return CapturedPhoto(image: image, source: .sample)
    }
}
