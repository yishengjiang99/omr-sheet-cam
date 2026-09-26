// omr-test — thin, non-interactive fixture runner (docs/TESTING.md "Addendum: agent / CLI TDD loop").
//
//   omr-test --no-onnx [--fixtures DIR] [--tier TIER] [fixtures/<id> | <id> ...]
//       Writer-only: expected.tokens.json → SMFWriter → SMFNoteReader → diff expected.notes.csv.
//   omr-test [--fixtures DIR] [--models DIR] [fixtures/<id> ...]
//       ONNX path (staff image → tokens). Exits 3 where no ORT backend is linked.
//   omr-test decode-staff <staff.npy | staff.f32 | staff.png> [--models DIR] [--json]
//       Encoder → DecoderLoop end to end; prints the raw decoded token streams.
//
// Exit codes: 0 all selected fixtures passed (SKIP does not fail) · 1 a fixture failed ·
//             2 usage / input error · 3 ONNX path not runnable on this platform yet.
import Foundation
import OMRHomrIOS

#if canImport(OnnxRuntimeBindings) || canImport(onnxruntime_objc)
typealias PlatformORTBackend = ORTObjCSession
#endif
// TODO(ORTCSession): on Linux, alias the app engineer's `ORTCSession` (branch ios/ort-c-linux)
// here once it is on main; until then the ONNX path exits 3 on Linux.

// MARK: - Output / exit helpers

func out(_ s: String) { print(s) }
func err(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }
func exitUsage(_ msg: String) -> Never {
    err("omr-test: \(msg)")
    err(usage)
    exit(2)
}
func exitNotRunnable(_ detail: String) -> Never {
    out("ONNX path not runnable on this platform yet")
    err("omr-test: \(detail)")
    exit(3)
}

let usage = """
usage: omr-test --no-onnx [--fixtures DIR] [--tier TIER] [fixtures/<id> | <id> ...]
       omr-test [--fixtures DIR] [--models DIR] [fixtures/<id> ...]       (ONNX path)
       omr-test decode-staff <staff.npy|staff.f32|staff.png> [--models DIR] [--json]
exit: 0 pass · 1 fail · 2 usage/input error · 3 ONNX path not runnable on this platform yet
"""

// MARK: - Arg parsing

var args = Array(CommandLine.arguments.dropFirst())
var noONNX = false
var fixturesOverride: String?
var modelsOverride: String?
var tierFilter: String?
var jsonOut = false
var positional: [String] = []
while !args.isEmpty {
    let a = args.removeFirst()
    switch a {
    case "--no-onnx": noONNX = true
    case "--json": jsonOut = true
    case "--fixtures":
        guard !args.isEmpty else { exitUsage("--fixtures needs a directory") }
        fixturesOverride = args.removeFirst()
    case "--models":
        guard !args.isEmpty else { exitUsage("--models needs a directory") }
        modelsOverride = args.removeFirst()
    case "--tier":
        guard !args.isEmpty else { exitUsage("--tier needs a value") }
        tierFilter = args.removeFirst()
    case "-h", "--help":
        out(usage)
        exit(0)
    default:
        if a.hasPrefix("-") { exitUsage("unknown option \(a)") }
        positional.append(a)
    }
}

// MARK: - Repo discovery

let fm = FileManager.default
let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)

func isDir(_ url: URL) -> Bool {
    var d: ObjCBool = false
    return fm.fileExists(atPath: url.path, isDirectory: &d) && d.boolValue
}

/// Walk up from cwd until `<dir>/<name>` exists.
func findUp(_ name: String) -> URL? {
    var dir = cwd.standardizedFileURL
    while true {
        let c = dir.appendingPathComponent(name)
        if isDir(c) { return c }
        let parent = dir.deletingLastPathComponent()
        if parent.path == dir.path { return nil }
        dir = parent
    }
}

func resolveDir(_ override: String?, _ name: String) -> URL? {
    if let o = override {
        let u = URL(fileURLWithPath: o, relativeTo: cwd).standardizedFileURL
        return isDir(u) ? u : nil
    }
    return findUp(name)
}

// MARK: - Model discovery + backend

struct ModelFiles { var encoderFP16: URL; var decoderFP32: URL }

func findModels() -> ModelFiles? {
    guard let dir = resolveDir(modelsOverride, "models"),
          let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return nil }
    let enc = names.filter { $0.hasPrefix("encoder_") && $0.hasSuffix("_fp16.onnx") }.sorted().last
    let dec = names.filter { $0.hasPrefix("decoder_") && $0.hasSuffix(".onnx") && !$0.hasSuffix("_fp16.onnx") }
        .sorted().last
    guard let enc, let dec else { return nil }
    return ModelFiles(encoderFP16: dir.appendingPathComponent(enc), decoderFP32: dir.appendingPathComponent(dec))
}

/// Encoder (CoreML EP w/ CPU fallback on Apple) → fp32 cast → Decoder (CPU fp32) → symbols.
func decodeStaff(normalized: Data, models: ModelFiles, vocab: HomrVocabulary) throws -> [EncodedSymbol] {
    #if canImport(OnnxRuntimeBindings) || canImport(onnxruntime_objc)
    let encoder = try EncoderSession.open(PlatformORTBackend.self, fp16ModelURL: models.encoderFP16)
    let decoder = try DecoderSession.open(PlatformORTBackend.self, vocabulary: vocab, modelURL: models.decoderFP32)
    let context = try encoder.generateContext(staffImageNormalized: normalized).castToFP32ForDecoder()
    let runner = try decoder.makeStepRunner(context: context)
    return try DecoderLoop(vocabulary: vocab).generate(context: context, stepRunner: runner)
    #else
    exitNotRunnable("no ORTSessionBackend is linked on this platform (Linux needs ORTCSession from ios/ort-c-linux)")
    #endif
}

func requireONNX() -> ModelFiles {
    #if !(canImport(OnnxRuntimeBindings) || canImport(onnxruntime_objc))
    exitNotRunnable("no ORTSessionBackend is linked on this platform (Linux needs ORTCSession from ios/ort-c-linux)")
    #else
    guard let m = findModels() else {
        exitNotRunnable("pinned models not found (run scripts/fetch-models or pass --models DIR)")
    }
    return m
    #endif
}

// MARK: - Staff tensor input

/// Load a normalized fp32 NCHW [1,1,256,1280] staff tensor (little-endian bytes).
func loadStaffTensor(_ path: String) -> Data {
    let url = URL(fileURLWithPath: path, relativeTo: cwd)
    let want = StaffInputSpec.nchwShape.reduce(1, *) * 4
    switch url.pathExtension.lowercased() {
    case "f32", "bin", "raw":
        guard let d = try? Data(contentsOf: url) else { exitUsage("cannot read \(path)") }
        guard d.count == want else { exitUsage("\(path): \(d.count) bytes, want \(want) (fp32 \(StaffInputSpec.nchwShape))") }
        return d
    case "npy":
        guard let d = try? Data(contentsOf: url) else { exitUsage("cannot read \(path)") }
        return parseNPY(d, path: path, wantBytes: want)
    case "png", "jpg", "jpeg":
        exitUsage("""
        \(path): image decode is not built into omr-test. Convert first (homr canvas + ConvertToArray):
          python3 tools/oracle/staff_png_to_tensor.py \(path) staff.npy && omr-test decode-staff staff.npy
        """)
    default:
        exitUsage("\(path): expected .npy, .f32 or .png")
    }
}

/// Minimal .npy v1/v2/v3 reader: little-endian float32, C order, 1*1*256*1280 elements.
func parseNPY(_ d: Data, path: String, wantBytes: Int) -> Data {
    let b = [UInt8](d)
    guard b.count > 10, b[0] == 0x93, String(bytes: b[1..<6], encoding: .ascii) == "NUMPY" else {
        exitUsage("\(path): not a .npy file")
    }
    let major = b[6]
    let headerLen: Int
    let start: Int
    if major == 1 {
        headerLen = Int(b[8]) | Int(b[9]) << 8
        start = 10
    } else {
        guard b.count > 12 else { exitUsage("\(path): truncated .npy") }
        headerLen = Int(b[8]) | Int(b[9]) << 8 | Int(b[10]) << 16 | Int(b[11]) << 24
        start = 12
    }
    guard b.count >= start + headerLen,
          let header = String(bytes: b[start..<(start + headerLen)], encoding: .ascii) else {
        exitUsage("\(path): bad .npy header")
    }
    guard header.contains("'<f4'"), header.contains("'fortran_order': False") else {
        exitUsage("\(path): need little-endian float32 C-order (<f4); header \(header)")
    }
    let body = d.subdata(in: (start + headerLen)..<d.count)
    guard body.count == wantBytes else {
        exitUsage("\(path): \(body.count) data bytes, want \(wantBytes) (fp32 \(StaffInputSpec.nchwShape))")
    }
    return body
}

// MARK: - Fixtures

struct TokenFile: Decodable {
    var status: String?
    var symbols: [OracleSymbolFields]
}

struct Note: Hashable, Comparable, CustomStringConvertible {
    var tick: Int, pitch: Int, duration: Int, staff: Int?
    static func < (a: Note, b: Note) -> Bool {
        (a.tick, a.staff ?? -1, a.pitch, a.duration) < (b.tick, b.staff ?? -1, b.pitch, b.duration)
    }
    var description: String {
        "(t\(tick) p\(pitch) d\(duration)" + (staff.map { " s\($0)" } ?? "") + ")"
    }
}

func readMeta(_ dir: URL) -> [String: String] {
    guard let s = try? String(contentsOf: dir.appendingPathComponent("meta.yaml"), encoding: .utf8) else { return [:] }
    var m: [String: String] = [:]
    for line in s.split(separator: "\n") where !line.hasPrefix(" ") && !line.hasPrefix("#") {
        guard let i = line.firstIndex(of: ":") else { continue }
        let k = line[..<i].trimmingCharacters(in: .whitespaces)
        var v = line[line.index(after: i)...].trimmingCharacters(in: .whitespaces)
        if v.hasPrefix("\""), v.hasSuffix("\""), v.count >= 2 { v = String(v.dropFirst().dropLast()) }
        m[k] = v
    }
    return m
}

func readCSV(_ url: URL) throws -> [Note] {
    let s = try String(contentsOf: url, encoding: .utf8)
    var outNotes: [Note] = []
    for (i, line) in s.split(whereSeparator: \.isNewline).enumerated() {
        let f = line.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        if i == 0 && f.first == "tick" { continue }
        guard f.count >= 4, let t = Int(f[0]), let p = Int(f[1]), let d = Int(f[2]), let st = Int(f[3]) else {
            throw NSError(domain: "omr-test", code: 2, userInfo: [NSLocalizedDescriptionKey: "\(url.lastPathComponent):\(i + 1): bad row '\(line)'"])
        }
        outNotes.append(Note(tick: t, pitch: p, duration: d, staff: st))
    }
    return outNotes
}

func levenshtein<T: Equatable>(_ a: [T], _ b: [T]) -> Int {
    if a.isEmpty { return b.count }
    if b.isEmpty { return a.count }
    var prev = Array(0...b.count)
    var cur = [Int](repeating: 0, count: b.count + 1)
    for i in 1...a.count {
        cur[0] = i
        for j in 1...b.count {
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
        }
        swap(&prev, &cur)
    }
    return prev[b.count]
}

enum Verdict: String { case pass = "PASS", fail = "FAIL", skip = "SKIP" }

/// Writer-only run of one fixture.
func runWriterOnly(id: String, dir: URL, tier: String, vocab: HomrVocabulary) -> Verdict {
    let tokensURL = dir.appendingPathComponent("expected.tokens.json")
    let csvURL = dir.appendingPathComponent("expected.notes.csv")
    guard let data = try? Data(contentsOf: tokensURL),
          let tf = try? JSONDecoder().decode(TokenFile.self, from: data) else {
        out("SKIP \(id) [\(tier)] no readable expected.tokens.json")
        return .skip
    }
    let status = tf.status ?? "unknown"
    if status == "stub" || status == "awaiting_oracle_export" || status != "complete" || tf.symbols.isEmpty {
        out("SKIP \(id) [\(tier)] tokens status=\(status) symbols=\(tf.symbols.count) — no writer input")
        return .skip
    }
    guard let expected = try? readCSV(csvURL) else {
        out("FAIL \(id) [\(tier)] cannot read expected.notes.csv")
        return .fail
    }
    // Vocab gate: never write tokens outside vocabulary.json.
    var vocabErrors: [String] = []
    for (i, s) in tf.symbols.enumerated() {
        for (field, value, table) in [
            ("rhythm", s.rhythm, vocab.rhythm), ("pitch", s.pitch, vocab.pitch), ("lift", s.lift, vocab.lift),
            ("articulation", s.articulation, vocab.articulation), ("slur", s.slur, vocab.slur),
            ("position", s.position, vocab.position),
        ] where table[value] == nil {
            vocabErrors.append("#\(i) \(field)='\(value)'")
        }
    }

    let symbols = tf.symbols.map { EncodedSymbol(oracleFields: $0) }
    let smf = SMFWriter().write(symbols: symbols)
    let contents: SMFNoteReader.Contents
    do {
        contents = try SMFNoteReader.read(from: smf)
    } catch {
        out("FAIL \(id) [\(tier)] SMFNoteReader: \(error)")
        return .fail
    }
    let compareStaff = contents.noteTrackCount > 1
    let got = contents.notes.map {
        Note(tick: $0.tick, pitch: $0.pitch, duration: $0.duration, staff: compareStaff ? contents.staff(of: $0) : nil)
    }.sorted()
    let want = expected.map {
        Note(tick: $0.tick, pitch: $0.pitch, duration: $0.duration, staff: compareStaff ? $0.staff : nil)
    }.sorted()
    let midiDist = levenshtein(got, want)

    // Multiset diff for the report.
    var remaining = want
    var extra: [Note] = []
    for n in got {
        if let i = remaining.firstIndex(of: n) { remaining.remove(at: i) } else { extra.append(n) }
    }
    let verdict: Verdict = tier == "snapshot" ? .pass : (midiDist == 0 && vocabErrors.isEmpty ? .pass : .fail)
    let fields = compareStaff ? "tick,pitch,duration,staff" : "tick,pitch,duration"
    out("\(verdict.rawValue) \(id) [\(tier)] token_edit=n/a midi_edit=\(midiDist) notes=\(got.count)/\(want.count) "
        + "tracks=\(contents.parsedTrackCount) compared=(\(fields))")
    for e in vocabErrors { out("    vocab: not in vocabulary.json: \(e)") }
    for n in remaining { out("    - missing \(n)") }
    for n in extra { out("    + extra   \(n)") }
    return verdict
}

// MARK: - Commands

let vocab: HomrVocabulary
do {
    vocab = try TokenizerLoader.loadVocabulary()
} catch {
    err("omr-test: cannot load vocabulary: \(error)")
    exit(2)
}

if positional.first == "decode-staff" {
    guard positional.count == 2 else { exitUsage("decode-staff needs exactly one input file") }
    let models = requireONNX()
    let tensor = loadStaffTensor(positional[1])
    do {
        let symbols = try decodeStaff(normalized: tensor, models: models, vocab: vocab)
        if jsonOut {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            let body = try enc.encode(OracleSymbolSequence(encoded: symbols).symbols)
            out(String(decoding: body, as: UTF8.self))
        } else {
            out("# \(symbols.count) symbols: index rhythm pitch lift articulation slur position")
            for (i, s) in symbols.enumerated() {
                out("\(i)\t\(s.rhythm)\t\(s.pitch)\t\(s.lift)\t\(s.articulation)\t\(s.slur)\t\(s.position)")
            }
        }
        exit(0)
    } catch {
        err("omr-test: decode-staff failed: \(error)")
        exit(1)
    }
}

guard let fixturesRoot = resolveDir(fixturesOverride, "fixtures") else {
    exitUsage("fixtures/ not found walking up from \(cwd.path) (use --fixtures DIR)")
}

var selected: [String]
if positional.isEmpty {
    selected = ((try? fm.contentsOfDirectory(atPath: fixturesRoot.path)) ?? [])
        .filter { isDir(fixturesRoot.appendingPathComponent($0)) }
        .sorted()
} else {
    selected = positional.map { p in
        let trimmed = p.hasSuffix("/") ? String(p.dropLast()) : p
        return URL(fileURLWithPath: trimmed).lastPathComponent
    }
    for id in selected where !isDir(fixturesRoot.appendingPathComponent(id)) {
        exitUsage("no fixture '\(id)' under \(fixturesRoot.path)")
    }
}

if !noONNX {
    _ = requireONNX()
    // ONNX fixture path needs a staff tensor per fixture (input.png → homr canvas) and a
    // committed oracle token file; not wired until an ORT backend runs on this platform.
    exitNotRunnable("fixture ONNX path requires a linked ORT backend + staff tensors; use --no-onnx or decode-staff")
}

out("omr-test --no-onnx: writer-only (expected.tokens.json → SMFWriter → SMFNoteReader vs expected.notes.csv)")
out("fixtures: \(fixturesRoot.path)")
out("tokens: expected.tokens.json is the writer INPUT; no decoded or committed oracle tokens are compared "
    + "without ONNX, so token_edit=n/a")
var counts: [Verdict: Int] = [:]
for id in selected {
    let dir = fixturesRoot.appendingPathComponent(id)
    let tier = readMeta(dir)["match_tier"] ?? "exact_tokens"
    if let t = tierFilter, t != tier { continue }
    let v = runWriterOnly(id: id, dir: dir, tier: tier, vocab: vocab)
    counts[v, default: 0] += 1
}
let pass = counts[.pass] ?? 0, fail = counts[.fail] ?? 0, skip = counts[.skip] ?? 0
out("summary: \(pass) PASS, \(fail) FAIL, \(skip) SKIP")
exit(fail > 0 ? 1 : 0)
