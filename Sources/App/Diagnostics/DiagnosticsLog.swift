import Combine
import Darwin
import Foundation
import OMRHomrIOS
import os

/// One in-app diagnostics event (also mirrored to os_log).
struct DiagnosticsEvent: Codable, Hashable, Identifiable, Sendable {
    enum Level: String, Codable, CaseIterable, Sendable { case info, warn, error }
    enum Category: String, Codable, CaseIterable, Sendable {
        case app, warmup, gate1, capture, recognition, playback, feedback
    }

    var id = UUID()
    var date: Date
    var level: Level
    var category: Category
    var message: String
    /// Optional structured fields (flat string map; stable keys per category, see call sites).
    var payload: [String: String]?

    init(date: Date = Date(), level: Level, category: Category, message: String, payload: [String: String]? = nil) {
        self.date = date
        self.level = level
        self.category = category
        self.message = message
        self.payload = payload
    }
}

/// In-memory + JSON-lines event log (`Application Support/diagnostics/events.jsonl`).
///
/// Thread-safe: `record` may be called from any thread / queue. Memory keeps the newest
/// `maxEntries`; the file is compacted back to the newest `maxEntries` (and under `maxBytes`)
/// once it grows past 125% of the entry cap or past `maxBytes`. File I/O runs on a private
/// serial queue. UI observers get `objectWillChange` on the main thread.
final class DiagnosticsLog: ObservableObject, @unchecked Sendable {
    static let shared = DiagnosticsLog(directory: DiagnosticsLog.defaultDirectory())

    let fileURL: URL?
    let maxEntries: Int
    let maxBytes: Int
    private let mirrorToOSLog: Bool
    private let lock = NSLock()
    private var entries: [DiagnosticsEvent] = []
    private var fileLines = 0
    private var fileBytes = 0
    private let io = DispatchQueue(label: "com.ragnus.vp.diagnostics.log", qos: .utility)
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.ragnus.vp"

    /// `directory == nil` → memory only.
    init(directory: URL?, maxEntries: Int = 2000, maxBytes: Int = 5 * 1024 * 1024, mirrorToOSLog: Bool = true) {
        self.maxEntries = maxEntries
        self.maxBytes = maxBytes
        self.mirrorToOSLog = mirrorToOSLog
        if let directory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            fileURL = directory.appendingPathComponent("events.jsonl")
        } else {
            fileURL = nil
        }
        load()
    }

    static func defaultDirectory() -> URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("diagnostics", isDirectory: true)
    }

    // MARK: - Recording

    func record(_ event: DiagnosticsEvent) {
        lock.lock()
        entries.append(event)
        if entries.count > maxEntries { entries.removeFirst(entries.count - maxEntries) }
        lock.unlock()
        if mirrorToOSLog { Self.osLog(event) }
        io.async { self.append(event) }
        notify()
    }

    func record(
        _ level: DiagnosticsEvent.Level, _ category: DiagnosticsEvent.Category, _ message: String,
        payload: [String: String]? = nil
    ) {
        record(DiagnosticsEvent(level: level, category: category, message: message, payload: payload))
    }

    /// An error that reached a UI boundary: full `String(describing:)`, localized text and type.
    func record(error: Error, category: DiagnosticsEvent.Category, context: String, payload: [String: String] = [:]) {
        var p = payload
        p["error"] = String(describing: error)
        p["localized"] = error.localizedDescription
        p["type"] = String(reflecting: type(of: error))
        record(.error, category, "\(context): \(error)", payload: p)
    }

    /// Newest last.
    var events: [DiagnosticsEvent] {
        lock.lock(); defer { lock.unlock() }
        return entries
    }

    func clear() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
        io.async {
            guard let url = self.fileURL else { return }
            try? Data().write(to: url, options: .atomic)
            self.fileLines = 0
            self.fileBytes = 0
        }
        notify()
    }

    /// Waits for pending file writes (tests, crash handler).
    func flush() { io.sync {} }

    /// Records uncaught Objective-C exceptions (flushed synchronously before the crash).
    static func installUncaughtExceptionHandler() {
        NSSetUncaughtExceptionHandler { exception in
            DiagnosticsLog.shared.record(
                .error, .app, "uncaught exception \(exception.name.rawValue): \(exception.reason ?? "")",
                payload: ["stack": exception.callStackSymbols.prefix(15).joined(separator: "\n")]
            )
            DiagnosticsLog.shared.flush()
        }
    }

    // MARK: - File (on `io`)

    private func load() {
        guard let url = fileURL, let data = try? Data(contentsOf: url), !data.isEmpty else { return }
        let decoder = Self.decoder
        let lines = data.split(separator: UInt8(ascii: "\n"))
        let loaded = lines.compactMap { try? decoder.decode(DiagnosticsEvent.self, from: Data($0)) }
        entries = Array(loaded.suffix(maxEntries))
        fileLines = lines.count
        fileBytes = data.count
        if fileLines > maxEntries || fileBytes > maxBytes { compact() }
    }

    private func append(_ event: DiagnosticsEvent) {
        guard let url = fileURL, var line = try? Self.encoder.encode(event) else { return }
        line.append(UInt8(ascii: "\n"))
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: url, options: .atomic)
        }
        fileLines += 1
        fileBytes += line.count
        if fileLines > maxEntries + maxEntries / 4 || fileBytes > maxBytes { compact() }
    }

    /// Rewrites the file with its newest `maxEntries` lines, dropping oldest until under 80% of
    /// `maxBytes` (headroom so the next appends don't trigger another rewrite). Works from the
    /// file itself, so events still queued for `append` are never duplicated.
    private func compact() {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return }
        var lines = Array(data.split(separator: UInt8(ascii: "\n")).suffix(maxEntries))
        var total = lines.reduce(0) { $0 + $1.count + 1 }
        var drop = 0
        while total > maxBytes * 4 / 5, drop < lines.count {
            total -= lines[drop].count + 1
            drop += 1
        }
        lines.removeFirst(drop)
        var out = Data(capacity: total)
        for l in lines { out.append(contentsOf: l); out.append(UInt8(ascii: "\n")) }
        try? out.write(to: url, options: .atomic)
        fileLines = lines.count
        fileBytes = out.count
    }

    private func notify() {
        if Thread.isMainThread { objectWillChange.send() } else {
            DispatchQueue.main.async { self.objectWillChange.send() }
        }
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private static func osLog(_ e: DiagnosticsEvent) {
        let logger = Logger(subsystem: subsystem, category: e.category.rawValue)
        let payload = e.payload.map { p in p.keys.sorted().map { "\($0)=\(p[$0]!)" }.joined(separator: " ") } ?? ""
        switch e.level {
        case .info: logger.notice("\(e.message, privacy: .public) \(payload, privacy: .public)")
        case .warn: logger.warning("\(e.message, privacy: .public) \(payload, privacy: .public)")
        case .error: logger.error("\(e.message, privacy: .public) \(payload, privacy: .public)")
        }
    }
}

/// Device / build facts for the log header and the prompt.
struct DeviceInfo: Codable, Equatable, Sendable {
    var model: String
    var os: String
    var appVersion: String
    var build: String
    var ortVersion: String

    static let current: DeviceInfo = {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let info = Bundle.main.infoDictionary ?? [:]
        return DeviceInfo(
            model: machineIdentifier(),
            os: "iOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)",
            appVersion: info["CFBundleShortVersionString"] as? String ?? "?",
            build: info["CFBundleVersion"] as? String ?? "?",
            ortVersion: ORTCSession.runtimeVersion
        )
    }()

    /// `utsname.machine` (e.g. `iPhone16,1`); on the simulator the simulated model + " (Simulator)".
    static func machineIdentifier() -> String {
        if let sim = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return "\(sim) (Simulator)" }
        var u = utsname()
        uname(&u)
        return withUnsafeBytes(of: &u.machine) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
    }

    var payload: [String: String] {
        ["model": model, "os": os, "app": appVersion, "build": build, "ort": ortVersion]
    }

    var headerLine: String { "\(model) · \(os) · v\(appVersion) (\(build)) · ORT \(ortVersion)" }
}
