import Foundation
import OMRHomrIOS

/// App-owned CoreML compiled-model cache (`<Application Support>/coreml-cache/`), passed to
/// `ORTCSession(modelURL:provider:cacheDirectory:cacheKey:)` for the ENCODER only (never the decoder;
/// SegNet stays on the plain CoreML EP path OMRHomrIOS picks). ORT writes `<root>/<key>/…`,
/// key = the model's SHA-256 (`COREML_CACHE_KEY`), so an app update (new container path) still hits.
///
/// The package leaves folder hygiene to the owner:
/// - root created on demand and excluded from iCloud / iTunes backup;
/// - `<key>.complete` marker written only after the session was created; an entry without it (jetsam
///   mid-compile) is deleted before the next create, since ORT would reuse the half entry and fail;
/// - entries whose key is not a model in use are deleted (stale after a model bump).
/// Callers serialize creation per model (warmup creates sessions one after another).
struct CoreMLCacheStore: Sendable {
    let root: URL

    /// `<Application Support>/coreml-cache/`.
    static func defaultRoot() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("coreml-cache", isDirectory: true)
    }

    /// Creates `root` if needed and marks it excluded from backup.
    static func prepare(root: URL? = nil) throws -> CoreMLCacheStore {
        let url = try root ?? defaultRoot()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var u = url
        try u.setResourceValues(values)
        return CoreMLCacheStore(root: url)
    }

    static func isExcludedFromBackup(_ url: URL) -> Bool {
        var u = url
        u.removeAllCachedResourceValues()
        return (try? u.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup) == true
    }

    func entry(_ key: String) -> URL { root.appendingPathComponent(key, isDirectory: true) }
    func marker(_ key: String) -> URL { root.appendingPathComponent("\(key).complete") }

    enum State: String { case hit, miss, incomplete }

    /// `hit` = complete entry present; `incomplete` = folder without marker (deleted here → cold compile);
    /// `miss` = nothing cached.
    func prepareEntry(_ key: String) -> State {
        let fm = FileManager.default
        let hasEntry = fm.fileExists(atPath: entry(key).path)
        let hasMarker = fm.fileExists(atPath: marker(key).path)
        switch (hasEntry, hasMarker) {
        case (true, true): return .hit
        case (true, false):
            try? fm.removeItem(at: entry(key))
            return .incomplete
        case (false, true):
            try? fm.removeItem(at: marker(key))
            return .miss
        case (false, false): return .miss
        }
    }

    func markComplete(_ key: String) {
        FileManager.default.createFile(atPath: marker(key).path, contents: Data())
    }

    /// Deletes the entry and its marker (after a failed create on a cached entry).
    func remove(_ key: String) {
        try? FileManager.default.removeItem(at: entry(key))
        try? FileManager.default.removeItem(at: marker(key))
    }

    /// Deletes entries / markers whose key is not in `keep`. Returns the removed names.
    @discardableResult
    func removeStale(keeping keep: Set<String>) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        var removed: [String] = []
        for n in names {
            let key = n.hasSuffix(".complete") ? String(n.dropLast(".complete".count)) : n
            guard !keep.contains(key) else { continue }
            try? FileManager.default.removeItem(at: root.appendingPathComponent(n))
            removed.append(n)
        }
        return removed
    }
}
