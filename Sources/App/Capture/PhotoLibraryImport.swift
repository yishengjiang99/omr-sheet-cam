import Photos
import PhotosUI
import UIKit

/// Shared photo-library → upright `UIImage` path used by Library (home) and Camera.
enum PhotoLibraryImport {
    enum LoadError: Error, LocalizedError {
        case noData
        case unsupported
        case cancelled
        case underlying(Error)

        var errorDescription: String? {
            switch self {
            case .noData: return "Could not load that photo"
            case .unsupported: return "Unsupported image"
            case .cancelled: return "Photo load cancelled"
            case .underlying(let e): return e.localizedDescription
            }
        }
    }

    /// Decode an upright image from a `PhotosPickerItem` (transferable, else PHAsset + iCloud).
    static func uprightImage(from item: PhotosPickerItem) async throws -> UIImage {
        guard let data = try await loadData(item) else { throw LoadError.noData }
        let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            UIImage(data: data).map(CaptureStore.normalizedUpright)
        }.value
        guard let image else { throw LoadError.unsupported }
        return image
    }

    /// Photo bytes for a picker item. `loadTransferable(type: Data.self)` throws "does not support
    /// import" for iCloud-only assets, so fall back to PHAsset with network access.
    static func loadData(_ item: PhotosPickerItem) async throws -> Data? {
        do {
            if let data = try await item.loadTransferable(type: Data.self) { return data }
        } catch {
            DiagnosticsLog.shared.record(.info, .capture,
                "Photos pick: transferable failed (\(error.localizedDescription)); trying PHAsset download")
        }
        guard let id = item.itemIdentifier,
              let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else {
            return nil
        }
        return try await withCheckedThrowingContinuation { cont in
            let opts = PHImageRequestOptions()
            opts.isNetworkAccessAllowed = true
            opts.deliveryMode = .highQualityFormat
            opts.version = .current
            var resumed = false
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: opts) { data, _, _, info in
                guard !resumed else { return }
                resumed = true
                if let data { cont.resume(returning: data); return }
                if let err = info?[PHImageErrorKey] as? Error { cont.resume(throwing: err); return }
                let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                cont.resume(throwing: cancelled ? LoadError.cancelled : LoadError.noData)
            }
        }
    }
}
