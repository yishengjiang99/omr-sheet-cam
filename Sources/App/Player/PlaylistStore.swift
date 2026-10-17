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

    /// Public-domain Ode to Joy and the Gate-1 C-major scale written by our own `SMFWriter`.
    static var bundled: [PlaylistSample] { [
        PlaylistSample(key: SampleMIDI.odeToJoyKey, title: "Ode to Joy (sample)") { try SampleMIDI.odeToJoy() },
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
    /// Where scan photos live (`Documents/captures`); `delete` removes a scan's JPEG from here.
    private let capturesDirectory: URL?

    /// Library order (also prev/next): your scans newest first (by date, then most recently
    /// added), then the samples.
    var entries: [PlaylistEntry] {
        let newestFirst = scans.enumerated()
            .sorted { ($0.element.date, $0.offset) > ($1.element.date, $1.offset) }
            .map(\.element)
        return newestFirst + samples
    }

    init(directory: URL, samples: [PlaylistSample] = PlaylistSample.bundled, log: DiagnosticsLog = .shared,
         capturesDirectory: URL? = try? CaptureStore.defaultDirectory()) {
        self.directory = directory
        self.capturesDirectory = capturesDirectory
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

    /// Set when `index.json` could not be read and the Library was rebuilt (F2.9); shown by the
    /// Library as a dismissible notice. Never set for a missing index (first launch).
    @Published private(set) var loadNotice: String?
    func dismissLoadNotice() { loadNotice = nil }

    private func loadIndex() -> [PlaylistEntry] {
        loadNotice = nil
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let all: [PlaylistEntry]
        do {
            let data = try Data(contentsOf: indexURL)
            all = try decoder.decode([PlaylistEntry].self, from: data)
        } catch {
            return recoverFromUnreadableIndex(error)
        }
        let present = all.filter { e in
            e.source == .scan && e.fileName.map { FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path) } == true
        }
        if present.count != all.count {
            log.record(.warn, .playback, "playlist: dropped \(all.count - present.count) entr(ies) with missing files", payload: ["kind": "playlist"])
        }
        return present
    }

    /// F2.9: keep the damaged file as `index.json.corrupt-<timestamp>` (so the next save can't destroy
    /// it), rebuild the entries from the saved `.mid` files, persist the rebuilt index and flag a notice.
    private func recoverFromUnreadableIndex(_ error: Error) -> [PlaylistEntry] {
        let fm = FileManager.default
        let backup = directory.appendingPathComponent("index.json.corrupt-\(CaptureStore.timestamp(Date()))")
        var backedUp = true
        do { try fm.moveItem(at: indexURL, to: backup) } catch {
            backedUp = false
            log.record(error: error, category: .playback, context: "playlist index backup", payload: ["backup": backup.lastPathComponent])
        }
        let rebuilt = rebuildEntriesFromMIDIFiles()
        if backedUp { try? writeIndex(rebuilt) }
        log.record(.warn, .playback, "playlist index.json unreadable (\(error)); backed up as \(backedUp ? backup.lastPathComponent : "NOT backed up"), rebuilt \(rebuilt.count) scan(s)",
                   payload: ["kind": "playlist_index_recovered", "rebuilt": "\(rebuilt.count)", "backup": backedUp ? backup.lastPathComponent : ""])
        let n = rebuilt.count
        loadNotice = "Your library list couldn't be read, so it was rebuilt from your saved music files "
            + "(\(n) scan\(n == 1 ? "" : "s") recovered; titles were reset). The damaged list was kept as \(backedUp ? backup.lastPathComponent : "a backup")."
        return rebuilt
    }

    /// Scans `<directory>/*.mid` (oldest first): date = file creation/modification, default title,
    /// capture = `<stem>.jpg` when it still exists in `captures/`. Unplayable files are skipped.
    private func rebuildEntriesFromMIDIFiles() -> [PlaylistEntry] {
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey])) ?? []
        var out: [PlaylistEntry] = []
        for url in urls where url.pathExtension.lowercased() == "mid" {
            let name = url.lastPathComponent
            guard let data = try? Data(contentsOf: url), let song = try? SMFSong(data: data) else { continue }
            let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
            let raw = values?.creationDate ?? values?.contentModificationDate ?? Date()
            let date = Date(timeIntervalSince1970: raw.timeIntervalSince1970.rounded(.down))
            let stem = (name as NSString).deletingPathExtension
            let jpg = "\(stem).jpg"
            let hasCapture = capturesDirectoryForRebuild.map { fm.fileExists(atPath: $0.appendingPathComponent(jpg).path) } ?? false
            out.append(PlaylistEntry(id: name, title: Self.defaultTitle(date), date: date, source: .scan,
                                     duration: song.durationSec, fileName: name, captureName: hasCapture ? jpg : nil))
        }
        return out.sorted { ($0.date, $0.id) < ($1.date, $1.id) }
    }

    private var capturesDirectoryForRebuild: URL? { try? CaptureStore.defaultDirectory() }

    private func saveIndex() throws { try writeIndex(scans) }

    private func writeIndex(_ entries: [PlaylistEntry]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(entries).write(to: indexURL, options: .atomic)
    }

    // MARK: Mutations

    /// Saves a scan's MIDI and appends it. `captureName` (`<stem>.jpg`) names the file, else the date.
    @discardableResult
    func addScan(midi: Data, title: String? = nil, captureName: String? = nil, date: Date = Date(),
                 layout: ScanLayout? = nil) throws -> PlaylistEntry {
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
        if let layout { saveLayout(layout, forMIDI: fileName) }
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
        if let f = removed.fileName {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(f))
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(ScanLayout.sidecarName(forMIDI: f)))
        }
        removeCaptureIfUnreferenced(removed)
        log.record(.info, .playback, "playlist: deleted \(removed.id)", payload: ["kind": "playlist_delete", "file": removed.id])
    }

    /// F2.7: the scan's photo goes with it (privacy: "Deleting a scan removes it"), unless another
    /// scan still points at the same JPEG. Best effort; only a bare file name inside `captures/`.
    private func removeCaptureIfUnreferenced(_ removed: PlaylistEntry) {
        guard let name = removed.captureName, !name.isEmpty, let dir = capturesDirectory,
              name == (name as NSString).lastPathComponent, name != ".", name != ".." else { return }
        guard !scans.contains(where: { $0.captureName == name }) else { return }
        let url = dir.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
            log.record(.info, .playback, "playlist: deleted capture \(name)", payload: ["kind": "playlist_delete_capture", "capture": name])
        } catch {
            log.record(error: error, category: .playback, context: "playlist capture delete", payload: ["capture": name])
        }
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

    // MARK: Note layout sidecar (`<stem>.layout.json`)

    /// Best effort: a scan without a sidecar still plays, just without Sheet mode.
    private func saveLayout(_ layout: ScanLayout, forMIDI fileName: String) {
        let name = ScanLayout.sidecarName(forMIDI: fileName)
        do {
            try layout.encoded().write(to: directory.appendingPathComponent(name), options: .atomic)
        } catch {
            log.record(error: error, category: .playback, context: "playlist layout save", payload: ["file": name])
        }
    }

    /// The scan's note layout, if it was saved with one (samples have none).
    func layout(for entry: PlaylistEntry) -> ScanLayout? {
        guard entry.source == .scan, let f = entry.fileName else { return nil }
        let url = directory.appendingPathComponent(ScanLayout.sidecarName(forMIDI: f))
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? ScanLayout.decode(data)
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
