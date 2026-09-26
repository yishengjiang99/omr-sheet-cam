import Combine
import Foundation
import SF2Player

/// One playable item: a saved scan (`Application Support/playlist/<name>.mid`) or a bundled sample.
struct PlaylistEntry: Codable, Hashable, Identifiable, Sendable {
    enum Source: String, Codable, Sendable { case scan, sample }

    /// Scans: the file name (`<name>.mid`, unique). Samples: `sample:<key>`.
    var id: String
    var title: String
    var date: Date
    var source: Source
    /// Seconds (SMF tempo map). 0 if unknown.
    var duration: Double
    /// Scans only: file name inside the playlist directory.
    var fileName: String?
    /// Capture this scan came from (`captures/<name>.jpg`), if any.
    var captureName: String?

    var isDeletable: Bool { source == .scan }
}

/// A bundled sample MIDI; `load` reads it from the app bundle (or generates it).
struct PlaylistSample {
    var key: String
    var title: String
    var load: () throws -> Data

    /// gbk's sweden.midi and the Gate-1 C-major scale written by our own `SMFWriter`.
    static var bundled: [PlaylistSample] { [
        PlaylistSample(key: "sweden", title: "Sweden (sample)") { try SampleMIDI.sweden() },
        PlaylistSample(key: "c-major-scale", title: "C major scale (sample)") { try SampleMIDI.cMajorScale() },
    ] }
}

/// Library = saved scans (newest first in `entries`) followed by the bundled samples (always
/// present, not deletable). `scans` keeps the order they were added. Scans live in `<directory>/<name>.mid` with `<directory>/index.json`
/// (`[PlaylistEntry]`, scans only). Missing files and a corrupt index are tolerated on reload.
@MainActor
final class PlaylistStore: ObservableObject {
    static let shared = PlaylistStore(directory: PlaylistStore.defaultDirectory())

    enum StoreError: Error, CustomStringConvertible {
        case notDeletable(String)
        case notFound(String)
        case invalidMIDI(String)

        var description: String {
            switch self {
            case let .notDeletable(t): return "\(t) is a bundled sample and can't be deleted"
            case let .notFound(id): return "playlist entry \(id) not found"
            case let .invalidMIDI(e): return "not a playable MIDI file: \(e)"
            }
        }
    }

    let directory: URL
    var indexURL: URL { directory.appendingPathComponent("index.json") }
    @Published private(set) var samples: [PlaylistEntry] = []
    @Published private(set) var scans: [PlaylistEntry] = []
    private let sampleSources: [PlaylistSample]
    private let log: DiagnosticsLog

    /// Library order (also prev/next): your scans newest first, then the samples.
    var entries: [PlaylistEntry] { scans.reversed() + samples }

    init(directory: URL, samples: [PlaylistSample] = PlaylistSample.bundled, log: DiagnosticsLog = .shared) {
        self.directory = directory
        self.sampleSources = samples
        self.log = log
        reload()
    }

    static func defaultDirectory() -> URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("playlist", isDirectory: true)
    }

    // MARK: Loading

    /// Re-reads index.json and rebuilds the sample list.
    func reload() {
        samples = sampleSources.map { s in
            let duration = (try? SMFSong(data: s.load()).durationSec) ?? 0
            return PlaylistEntry(id: "sample:\(s.key)", title: s.title, date: .distantPast, source: .sample, duration: duration)
        }
        scans = loadIndex()
    }

    private func loadIndex() -> [PlaylistEntry] {
        guard let data = try? Data(contentsOf: indexURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let all = try? decoder.decode([PlaylistEntry].self, from: data) else {
            log.record(.warn, .playback, "playlist index.json unreadable (\(data.count) B); starting empty", payload: ["kind": "playlist"])
            return []
        }
        let present = all.filter { e in
            e.source == .scan && e.fileName.map { FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path) } == true
        }
        if present.count != all.count {
            log.record(.warn, .playback, "playlist: dropped \(all.count - present.count) entr(ies) with missing files", payload: ["kind": "playlist"])
        }
        return present
    }

    private func saveIndex() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(scans).write(to: indexURL, options: .atomic)
    }

    // MARK: Mutations

    /// Saves a scan's MIDI and appends it. `captureName` (`<stem>.jpg`) names the file, else the date.
    @discardableResult
    func addScan(midi: Data, title: String? = nil, captureName: String? = nil, date: Date = Date()) throws -> PlaylistEntry {
        let duration: Double
        do { duration = try SMFSong(data: midi).durationSec } catch { throw StoreError.invalidMIDI("\(error)") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stem = captureName.map { ($0 as NSString).deletingPathExtension }.flatMap { $0.isEmpty || $0.hasPrefix("unsaved-") ? nil : $0 }
            ?? CaptureStore.timestamp(date)
        let fileName = uniqueFileName(stem: Self.sanitized(stem))
        try midi.write(to: directory.appendingPathComponent(fileName), options: .atomic)
        // Whole seconds: the index stores ISO 8601 dates, so reloaded entries compare equal.
        let stored = Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
        let entry = PlaylistEntry(
            id: fileName, title: title ?? Self.defaultTitle(date), date: stored, source: .scan,
            duration: duration, fileName: fileName, captureName: captureName
        )
        scans.append(entry)
        do {
            try saveIndex()
        } catch {
            scans.removeLast()
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(fileName))
            throw error
        }
        log.record(.info, .playback, "playlist: saved \(fileName) (\(midi.count) B, \(String(format: "%.1f", duration)) s)",
                   payload: ["kind": "playlist_add", "file": fileName, "bytes": "\(midi.count)", "duration": String(format: "%.2f", duration),
                             "capture": captureName ?? ""])
        return entry
    }

    /// Deletes a scan (file + index entry). Samples throw `.notDeletable`.
    func delete(_ entry: PlaylistEntry) throws {
        guard entry.isDeletable else { throw StoreError.notDeletable(entry.title) }
        guard let i = scans.firstIndex(where: { $0.id == entry.id }) else { throw StoreError.notFound(entry.id) }
        let removed = scans.remove(at: i)
        try saveIndex()
        if let f = removed.fileName { try? FileManager.default.removeItem(at: directory.appendingPathComponent(f)) }
        log.record(.info, .playback, "playlist: deleted \(removed.id)", payload: ["kind": "playlist_delete", "file": removed.id])
    }

    func entry(id: String) -> PlaylistEntry? { entries.first { $0.id == id } }

    /// Renames a scan (the Result title field / Save to Library).
    @discardableResult
    func rename(_ entry: PlaylistEntry, to title: String) throws -> PlaylistEntry {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard entry.isDeletable, !t.isEmpty else { return entry }
        guard let i = scans.firstIndex(where: { $0.id == entry.id }) else { throw StoreError.notFound(entry.id) }
        let old = scans[i]
        scans[i].title = t
        do { try saveIndex() } catch { scans[i] = old; throw error }
        return scans[i]
    }

    /// Case-insensitive title filter over `entries` (Library search).
    func search(_ query: String) -> [PlaylistEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? entries : entries.filter { $0.title.localizedCaseInsensitiveContains(q) }
    }

    func midiData(for entry: PlaylistEntry) throws -> Data {
        switch entry.source {
        case .scan:
            guard let f = entry.fileName else { throw StoreError.notFound(entry.id) }
            return try Data(contentsOf: directory.appendingPathComponent(f))
        case .sample:
            guard let s = sampleSources.first(where: { "sample:\($0.key)" == entry.id }) else { throw StoreError.notFound(entry.id) }
            return try s.load()
        }
    }

    /// Neighbor in `entries` order (nil at either end).
    func neighbor(of id: String, offset: Int) -> PlaylistEntry? {
        let all = entries
        guard let i = all.firstIndex(where: { $0.id == id }) else { return nil }
        let j = i + offset
        return all.indices.contains(j) ? all[j] : nil
    }

    // MARK: Helpers

    static func defaultTitle(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return "Scan \(f.string(from: date))"
    }

    static func sanitized(_ stem: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let s = String(stem.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        return s.isEmpty ? "scan" : s
    }

    private func uniqueFileName(stem: String) -> String {
        var name = "\(stem).mid", n = 2
        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path) || scans.contains(where: { $0.id == name }) {
            name = "\(stem)-\(n).mid"; n += 1
        }
        return name
    }
}
