import SwiftUI
import UIKit

/// Visual OMR comparison + accuracy feedback (List sections; embed in a `List`).
///
/// - Boxes (`layoutSource == attention`, `NoteLayout.pageRect` non-null): drawn on the photo,
///   colored by staff; tap = pitch label (Inspect) or toggle wrong (Mark wrong).
/// - No boxes (`midi-fallback`, today): a token-order strip under the image — markers spaced by
///   symbol index, clearly labeled approximate (the package never fabricates coordinates).
/// - List view: notes per staff with pitch names and durations.
struct OMRCompareView: View {
    let image: UIImage
    let details: RecognitionDetails
    let captureName: String
    /// Decoded symbol count (for the token-order strip); defaults to max symbolIndex + 1.
    var symbolCount: Int? = nil
    @Binding var feedback: OMRFeedback
    @Binding var toast: String?
    /// "Copy as prompt" etc. (Developer screens only; consumer Result hides them).
    var showsDeveloperTools = false

    enum Display: String, CaseIterable { case overlay = "Overlay", list = "List" }
    enum TapMode: String, CaseIterable { case inspect = "Inspect", markWrong = "Mark wrong" }

    @State private var display: Display = .overlay
    @State private var showOverlay = true
    @State private var tapMode: TapMode = .inspect
    @State private var selected: Int?

    static let palette: [Color] = [Theme.coral, .orange, .teal, .indigo, .pink, .green, .brown, .blue]
    static func color(staff: Int) -> Color { palette[((staff % palette.count) + palette.count) % palette.count] }

    private struct StaffGroup: Identifiable {
        var staff: Int
        var notes: [RecognizedNote]
        var id: Int { staff }
    }

    private var notesByStaff: [StaffGroup] {
        Set(details.notes.map(\.staffIndex)).sorted().map { s in
            StaffGroup(staff: s, notes: details.notes.filter { $0.staffIndex == s })
        }
    }

    private var staffIndices: [Int] {
        let fromNotes = Set(details.notes.map(\.staffIndex))
        return Array(Set(0..<max(details.staffCount, 0)).union(fromNotes)).sorted()
    }

    var body: some View {
        Group {
            Section {
                Picker("View", selection: $display) {
                    ForEach(Display.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                if display == .overlay {
                    Toggle("Show recognized notes", isOn: $showOverlay)
                    Picker("Tap", selection: $tapMode) {
                        ForEach(TapMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    overlayImage.listRowInsets(EdgeInsets())
                    if !details.hasBoxes && showOverlay { tokenStrip }
                    if let n = selectedNote { Text(label(n)).font(.footnote.monospaced()) }
                } else {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 220)
                        .listRowInsets(EdgeInsets())
                }
                Text(summaryLine)
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                ForEach(details.warnings, id: \.self) { w in
                    Label(w, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                }
            } header: {
                Text("Compare")
            }

            if display == .list {
                ForEach(notesByStaff) { group in
                    Section("Staff \(group.staff + 1) · \(group.notes.count) notes") {
                        ForEach(group.notes) { n in noteRow(n) }
                    }
                }
                if details.notes.isEmpty { Section { Text("No notes recognized").foregroundStyle(.secondary) } }
            }

            feedbackSection
        }
    }

    private var summaryLine: String {
        var s = "\(details.notes.count) notes · \(details.staffCount) staff"
        if details.staffCount != 1 { s += "s" }
        s += " · layout \(details.layoutSource)"
        if details.ms > 0 { s += String(format: " · %.0f ms", details.ms) }
        return s
    }

    // MARK: - Overlay

    private var pixelSize: CGSize {
        if let cg = image.cgImage { return CGSize(width: cg.width, height: cg.height) }
        return CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
    }

    private var selectedNote: RecognizedNote? { selected.flatMap { i in details.notes.first { $0.noteIndex == i } } }

    private var overlayImage: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .overlay {
                if showOverlay && details.hasBoxes {
                    GeometryReader { geo in
                        let sx = geo.size.width / max(pixelSize.width, 1)
                        let sy = geo.size.height / max(pixelSize.height, 1)
                        ForEach(details.notes.filter { $0.rect != nil }) { n in
                            let r = n.rect!
                            let frame = CGRect(x: r.minX * sx, y: r.minY * sy, width: max(r.width * sx, 8), height: max(r.height * sy, 8))
                            marker(n, isBox: true)
                                .frame(width: frame.width, height: frame.height)
                                .position(x: frame.midX, y: frame.midY)
                        }
                    }
                }
            }
    }

    /// Box-less layout: markers at `(symbolIndex + 0.5) / symbolCount` of the width, one row per staff.
    private var tokenStrip: some View {
        let count = max(symbolCount ?? ((details.notes.map(\.symbolIndex).max() ?? 0) + 1), 1)
        let rows = max(staffIndices.count, 1)
        return VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ForEach(details.notes) { n in
                    let row = staffIndices.firstIndex(of: n.staffIndex) ?? 0
                    marker(n, isBox: false)
                        .frame(width: 22, height: 22)
                        .position(
                            x: (CGFloat(n.symbolIndex) + 0.5) / CGFloat(count) * geo.size.width,
                            y: CGFloat(row) * 28 + 14
                        )
                }
            }
            .frame(height: CGFloat(rows) * 28)
            Text("Approximate positions (token order): layout \(details.layoutSource) has no note boxes yet.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func marker(_ n: RecognizedNote, isBox: Bool) -> some View {
        let wrong = isWrong(n)
        let c = wrong ? Color.red : Self.color(staff: n.staffIndex)
        return ZStack {
            if isBox {
                Rectangle().stroke(c, lineWidth: selected == n.noteIndex ? 3 : 1.5)
                    .background(Rectangle().fill(c.opacity(wrong ? 0.35 : 0.12)))
            } else {
                Circle().fill(c.opacity(wrong ? 0.9 : 0.75))
                Text(n.pitchName).font(.system(size: 7, weight: .bold)).foregroundStyle(.white).minimumScaleFactor(0.5)
            }
            if wrong { Image(systemName: "xmark").font(.caption2.weight(.bold)).foregroundStyle(.white) }
            if selected == n.noteIndex {
                Text(n.pitchName)
                    .font(.caption2.monospaced().weight(.bold))
                    .padding(2).background(.background.opacity(0.9), in: RoundedRectangle(cornerRadius: 3))
                    .offset(y: -22)
                    .fixedSize()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { tap(n) }
    }

    private func tap(_ n: RecognizedNote) {
        switch tapMode {
        case .inspect: selected = selected == n.noteIndex ? nil : n.noteIndex
        case .markWrong: toggleWrong(n); selected = n.noteIndex
        }
    }

    private func label(_ n: RecognizedNote) -> String {
        "#\(n.noteIndex) \(n.pitchName) \(n.durationName) · staff \(n.staffIndex + 1)\(isWrong(n) ? " · marked wrong" : "")"
    }

    private func noteRow(_ n: RecognizedNote) -> some View {
        HStack {
            Circle().fill(Self.color(staff: n.staffIndex)).frame(width: 8, height: 8)
            Text("#\(n.noteIndex)").font(.caption.monospaced()).foregroundStyle(.secondary).frame(width: 36, alignment: .leading)
            Text(n.pitchName).font(.body.monospaced().weight(.semibold)).frame(width: 44, alignment: .leading)
            Text(n.durationName).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button { toggleWrong(n) } label: {
                Image(systemName: isWrong(n) ? "xmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(isWrong(n) ? .red : .secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isWrong(n) ? "Unmark wrong" : "Mark wrong")
        }
    }

    // MARK: - Feedback

    private func isWrong(_ n: RecognizedNote) -> Bool { feedback.wrongNotes.contains { $0.noteIndex == n.noteIndex } }

    private func toggleWrong(_ n: RecognizedNote) {
        if let i = feedback.wrongNotes.firstIndex(where: { $0.noteIndex == n.noteIndex }) {
            feedback.wrongNotes.remove(at: i)
        } else {
            feedback.wrongNotes.append(.init(noteIndex: n.noteIndex, staffIndex: n.staffIndex, pitch: n.pitchName))
        }
    }

    private func staffVerdict(_ staff: Int) -> Binding<OMRFeedback.Verdict?> {
        Binding(
            get: { feedback.staffVerdicts.first { $0.staffIndex == staff }?.verdict },
            set: { v in
                feedback.staffVerdicts.removeAll { $0.staffIndex == staff }
                if let v { feedback.staffVerdicts.append(.init(staffIndex: staff, verdict: v)) }
                feedback.staffVerdicts.sort { $0.staffIndex < $1.staffIndex }
            }
        )
    }

    private var feedbackSection: some View {
        Section("Was the reading accurate?") {
            Picker("Overall", selection: $feedback.verdict) {
                Text("—").tag(OMRFeedback.Verdict?.none)
                ForEach(OMRFeedback.Verdict.allCases, id: \.self) { Text($0.label).tag(Optional($0)) }
            }
            .pickerStyle(.segmented)
            if staffIndices.count > 0 {
                ForEach(staffIndices, id: \.self) { s in
                    Picker("Staff \(s + 1)", selection: staffVerdict(s)) {
                        Text("—").tag(OMRFeedback.Verdict?.none)
                        ForEach(OMRFeedback.Verdict.allCases, id: \.self) { Text($0.label).tag(Optional($0)) }
                    }
                }
            }
            HStack {
                Text("Marked wrong: \(feedback.wrongNotes.count)")
                Spacer()
                if !feedback.wrongNotes.isEmpty {
                    Button("Clear marks") { feedback.wrongNotes.removeAll() }.buttonStyle(.borderless)
                }
            }
            .font(.footnote)
            TextField("What was wrong? (optional)", text: $feedback.note, axis: .vertical)
                .lineLimit(2...6)
            Button("Save feedback") { save() }
                .disabled(feedback.isEmpty)
            if showsDeveloperTools {
                CopyPromptButton(captureName: captureName, feedback: feedback, toast: $toast)
            }
        }
    }

    private func save() {
        var f = feedback
        f.captureName = captureName
        f.staffCount = details.staffCount
        f.noteCount = details.notes.count
        f.layoutSource = details.layoutSource
        f.date = Date()
        do {
            DiagnosticsLog.shared.record(try f.event())
            toast = "Feedback saved"
        } catch {
            DiagnosticsLog.shared.record(error: error, category: .feedback, context: "feedback encode")
            toast = "Could not save feedback"
        }
    }
}
