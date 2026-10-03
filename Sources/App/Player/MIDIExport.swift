import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// Share sheet item for a Library entry / the playing song: a `.mid` named after its title.
/// Scans are read from their playlist file only when the user actually shares.
struct MIDIExport: Transferable, Equatable, Sendable {
    enum Source: Equatable, Sendable {
        case file(URL)
        case data(Data)
    }

    var title: String
    var source: Source

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .midi) { export in
            SentTransferredFile(try export.writeTemporaryFile())
        }
    }

    /// "Ode to Joy (sample)" → "Ode to Joy (sample).mid": keeps spaces / letters, drops path separators.
    static func fileName(for title: String) -> String {
        let banned = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.newlines).union(.controlCharacters)
        let cleaned = String(title.unicodeScalars.map { banned.contains($0) ? "-" : Character($0) })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let stem = cleaned.isEmpty ? "Music" : String(cleaned.prefix(80))
        return stem + ".mid"
    }

    func midiData() throws -> Data {
        switch source {
        case let .file(url): return try Data(contentsOf: url)
        case let .data(d): return d
        }
    }

    /// Writes `<tmp>/midi-export/<uuid>/<title>.mid` (a fresh folder per share, so names never clash).
    func writeTemporaryFile() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("midi-export", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(Self.fileName(for: title))
        try midiData().write(to: url, options: .atomic)
        return url
    }
}

extension PlaylistStore {
    /// Share item for `entry` (scan file or bundled sample bytes); nil if the sample can't load.
    func export(for entry: PlaylistEntry) -> MIDIExport? {
        switch entry.source {
        case .scan:
            guard let f = entry.fileName else { return nil }
            return MIDIExport(title: entry.title, source: .file(directory.appendingPathComponent(f)))
        case .sample:
            guard let d = try? midiData(for: entry) else { return nil }
            return MIDIExport(title: entry.title, source: .data(d))
        }
    }
}
