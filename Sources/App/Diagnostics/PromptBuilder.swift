import Foundation

/// "Copy as prompt": concise Markdown summary of the diagnostics log for pasting into an AI chat.
///
/// Pure (events in, text out) so it is unit-tested. Reads the payload conventions written by the
/// app's call sites: `kind` = `session` / `summary` / `failed` (warmup), `result` / `error`
/// (gate1), `run` / `page_parse` (recognition); `capture` = capture file name.
enum PromptBuilder {
    struct Input {
        var device: DeviceInfo
        /// Oldest first (as `DiagnosticsLog.events`).
        var events: [DiagnosticsEvent]
        /// Result screen: focus recognition + feedback on this capture.
        var captureName: String? = nil
        /// Unsaved on-screen feedback; overrides the latest logged one.
        var feedback: OMRFeedback? = nil
        var maxBytes: Int = 4096
    }

    static let framing = "Please help diagnose: what is failing, the likely cause, and what to try next. App = iPhone OMR (photo of sheet music → MIDI) using homr models on ONNX Runtime."

    private struct Limits {
        var errors: Int
        var sessions: Bool
        var noteChars: Int
        var wrongNotes: Int
        var lineChars: Int
    }

    private static let tiers: [Limits] = [
        Limits(errors: 12, sessions: true, noteChars: 600, wrongNotes: 20, lineChars: 220),
        Limits(errors: 8, sessions: false, noteChars: 400, wrongNotes: 12, lineChars: 180),
        Limits(errors: 5, sessions: false, noteChars: 250, wrongNotes: 8, lineChars: 140),
        Limits(errors: 3, sessions: false, noteChars: 150, wrongNotes: 5, lineChars: 110),
    ]

    static func build(_ input: Input) -> String {
        var text = ""
        for limits in tiers {
            text = render(input, limits)
            if text.utf8.count <= input.maxBytes { return text }
        }
        return hardTruncate(text, maxBytes: input.maxBytes)
    }

    // MARK: - Rendering

    private static func render(_ input: Input, _ lim: Limits) -> String {
        let ev = input.events
        func clip(_ s: String) -> String { truncate(oneLine(s), lim.lineChars) }
        var out: [String] = []

        // Header
        let d = input.device
        let warmSummary = ev.last { $0.category == .warmup && ($0.payload?["kind"] == "summary" || $0.payload?["kind"] == "failed") }
        let providers = warmSummary?.payload?["providers"] ?? "unknown (no warmup yet)"
        out.append("# OMR Sheet Cam diagnostics")
        out.append(framing)
        out.append("- App v\(d.appVersion) (\(d.build)) · \(d.model) · \(d.os)")
        out.append("- ORT \(d.ortVersion) · providers: \(providers)")

        // Warmup
        out.append("")
        out.append("## Warmup (latest)")
        if let s = warmSummary {
            out.append("- \(clip(s.message))")
            if lim.sessions {
                let start = ev.lastIndex(of: s) ?? ev.endIndex
                // Session lines of this warmup run: walk back to the previous summary.
                var sessions: [DiagnosticsEvent] = []
                for e in ev[..<start].reversed() {
                    guard e.category == .warmup else { continue }
                    if e.payload?["kind"] == "summary" { break }
                    if e.payload?["kind"] == "session" { sessions.insert(e, at: 0) }
                }
                for e in sessions.suffix(3) { out.append("  - \(clip(e.message))") }
            }
        } else {
            out.append("- none recorded")
        }

        // Gate-1
        out.append("")
        out.append("## Gate-1 (latest)")
        let gate1: [DiagnosticsEvent] = ["npy", "png"].compactMap { kind in
            ev.last { $0.category == .gate1 && $0.payload?["input"] == kind }
        }
        if gate1.isEmpty { out.append("- not run") }
        for e in gate1 { out.append("- \(clip(e.message))") }

        // Recognition
        out.append("")
        out.append("## Last recognition")
        let rec = ev.last {
            $0.category == .recognition && $0.payload?["kind"] == "run"
                && (input.captureName == nil || $0.payload?["capture"] == input.captureName)
        }
        if let r = rec {
            out.append("- \(clip(r.message))")
            if let w = r.payload?["warnings"], !w.isEmpty { out.append("  - warnings: \(clip(w))") }
            if let e = r.payload?["error"], !e.isEmpty { out.append("  - error: \(clip(e))") }
        } else {
            out.append("- none")
        }

        // Page parse (PageRecognitionService `page_parse` events)
        out.append("")
        out.append("## Page parse (latest)")
        if let pp = ev.last(where: { $0.category == .recognition && $0.payload?["kind"] == "page_parse" }) {
            out.append(contentsOf: pageParseLines(pp.payload ?? [:], clip))
        } else {
            out.append("- none")
        }

        // SegNet self-test (Settings → Developer)
        out.append("")
        out.append("## SegNet self-test (latest)")
        out.append(contentsOf: segnetSelfTestLines(ev, clip))

        // Feedback
        var fb: OMRFeedback? = nil
        if let f = input.feedback, !f.isEmpty {
            fb = f
        } else {
            for e in ev.reversed() {
                guard let f = OMRFeedback(event: e) else { continue }
                if input.captureName == nil || f.captureName == input.captureName { fb = f; break }
            }
        }
        out.append("")
        out.append("## OMR accuracy feedback (user, visual compare)")
        if let f = fb {
            out.append(contentsOf: feedbackLines(f, lim))
        } else {
            out.append("- none given")
        }
        // Errors & warnings, deduped with counts (most frequent, then most recent).
        let problems = dedupe(ev.filter { $0.level != .info })
        out.append("")
        let total = problems.reduce(0) { $0 + $1.count }
        out.append("## Errors & warnings (\(problems.count) unique, \(total) total)")
        if problems.isEmpty { out.append("- none") }
        for p in problems.prefix(lim.errors) {
            out.append("- [\(p.level.rawValue)] \(p.category.rawValue)\(p.count > 1 ? " ×\(p.count)" : ""): \(clip(p.message))")
        }
        if problems.count > lim.errors { out.append("- … and \(problems.count - lim.errors) more") }

        return out.joined(separator: "\n") + "\n"
    }

    /// Latest `segnet_selftest` event → one line per variant (classes, min/max/NaN, ms, staffs or "unavailable: …").
    static func segnetSelfTestLines(_ ev: [DiagnosticsEvent], _ clip: (String) -> String) -> [String] {
        guard let e = ev.last(where: { $0.category == .recognition && $0.payload?["kind"] == "segnet_selftest" }),
              let q = e.payload else { return ["- not run"] }
        var out = ["- \(clip(e.message)) · \(q["page"] ?? "?")"]
        for v in SegNetSelfTest.Variant.allCases {
            if let line = q[v.rawValue] { out.append(clip("- \(v.rawValue): \(line)")) }
        }
        if let err = q["error"] { out.append(clip("- error: \(err)")) }
        return out
    }

    /// `page_parse` payload → prompt lines (outcome, timing, image, staffs, warnings, memory, stages, error).
    static func pageParseLines(_ q: [String: String], _ clip: (String) -> String) -> [String] {
        func v(_ k: String) -> String { q[k].flatMap { $0.isEmpty ? nil : $0 } ?? "?" }
        var out: [String] = []
        out.append("- \(v("outcome")) · \(v("ms")) ms (decode \(v("decode_ms")), parse \(v("parse_ms"))) · image \(v("image")) · staffCount \(v("staff_count")) · warnings \(v("warnings_count"))")
        if let src = q["source_format"] {
            out.append(clip("- input: \(src), EXIF orientation \(v("exif_orientation")), \(v("input_bytes")) B"))
        }
        var mem = "- memory (phys_footprint): before \(v("footprint_before_mb")) MB, after \(v("footprint_after_mb")) MB, peak \(v("peak_mb")) MB (\(v("peak_source")), \(v("samples")) samples"
        if let l = q["ledger_peak_mb"] { mem += ", lifetime ledger peak \(l) MB" }
        mem += ")"
        if let a = q["available_mb"] { mem += " · available \(a) MB" }
        out.append(clip(mem))
        var sess = "- session: \(v("session"))"
        if let b = q["session_build_ms"] { sess += " (\(b) ms)" }
        out.append(sess)
        if let st = q["stages"], !st.isEmpty { out.append("- stages ms: \(clip(st))") }
        if let w = q["warnings"], !w.isEmpty { out.append("- warnings: \(clip(w))") }
        if let e = q["error"], !e.isEmpty { out.append("- error: \(clip(e))") }
        return out
    }

    private static func feedbackLines(_ f: OMRFeedback, _ lim: Limits) -> [String] {
        var out: [String] = []
        out.append("- Capture: \(f.captureName) · staffCount \(f.staffCount) · noteCount \(f.noteCount)\(f.layoutSource.map { " · layout \($0)" } ?? "")")
        out.append("- Verdict: \(f.verdict?.label ?? "not set")")
        if !f.staffVerdicts.isEmpty {
            let s = f.staffVerdicts.sorted { $0.staffIndex < $1.staffIndex }
                .map { "staff \($0.staffIndex + 1) \($0.verdict.label.lowercased())" }.joined(separator: ", ")
            out.append("- Per staff: \(s)")
        }
        if f.wrongNotes.isEmpty {
            out.append("- Wrong-marked notes: 0")
        } else {
            let list = f.wrongNotes.sorted { $0.noteIndex < $1.noteIndex }
            var s = list.prefix(lim.wrongNotes)
                .map { "#\($0.noteIndex) \($0.pitch) (staff \($0.staffIndex + 1))" }.joined(separator: ", ")
            if list.count > lim.wrongNotes { s += ", … and \(list.count - lim.wrongNotes) more" }
            out.append("- Wrong-marked notes (\(list.count)): \(s)")
        }
        let note = oneLine(f.note).trimmingCharacters(in: .whitespaces)
        if !note.isEmpty { out.append("- Note: \"\(truncate(note, lim.noteChars))\"") }
        return out
    }

    struct Problem: Equatable {
        var level: DiagnosticsEvent.Level
        var category: DiagnosticsEvent.Category
        var message: String
        var count: Int
        var last: Date
    }

    /// Groups by (level, category, message); sorted by count desc, then most recent.
    static func dedupe(_ events: [DiagnosticsEvent]) -> [Problem] {
        var order: [String] = []
        var map: [String: Problem] = [:]
        for e in events {
            let key = "\(e.level.rawValue)|\(e.category.rawValue)|\(e.message)"
            if var p = map[key] {
                p.count += 1
                p.last = max(p.last, e.date)
                map[key] = p
            } else {
                order.append(key)
                map[key] = Problem(level: e.level, category: e.category, message: e.message, count: 1, last: e.date)
            }
        }
        return order.compactMap { map[$0] }.sorted {
            $0.count != $1.count ? $0.count > $1.count : $0.last > $1.last
        }
    }

    static func oneLine(_ s: String) -> String {
        s.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
    }

    static func truncate(_ s: String, _ n: Int) -> String {
        s.count <= n ? s : String(s.prefix(max(0, n - 1))) + "…"
    }

    static func hardTruncate(_ s: String, maxBytes: Int) -> String {
        let marker = "\n… (truncated)\n"
        var out = s
        while out.utf8.count + marker.utf8.count > maxBytes, !out.isEmpty { out.removeLast(max(1, out.count / 20)) }
        return out + marker
    }
}
