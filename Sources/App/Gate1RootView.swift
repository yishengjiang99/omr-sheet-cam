import SwiftUI
import OMRHomrIOS
import os

/// Gate-1 debug surface only — status, warmup, MIDI smoke.
/// No capture camera UI, no geometry overlays, no App Store polish.
struct Gate1RootView: View {
    @State private var statusLines: [String] = [
        "Gate-1 shell",
        "Package: OMRHomrIOS (AGPL)",
        "Scope: staff-only parse → MIDI smoke",
        "Models: bundled SegNet/Encoder fp16 (CoreML), Decoder fp32 (CPU)",
    ]
    @State private var lastError: String?
    @State private var midiPlayer = SimpleMIDIPlayer()
    @ObservedObject private var warmup = ModelWarmup.shared
    @State private var gate1Running = false
    @State private var gate1Verdict: String?
    @State private var gate1Detail: String?

    /// true when pushed inside another NavigationStack (Settings → Developer).
    let embedded: Bool

    init(embedded: Bool = false) {
        self.embedded = embedded
    }

    var body: some View {
        if embedded {
            content
        } else {
            NavigationStack { content }
        }
    }

    private var content: some View {
            List {
                Section("Tools") {
                    NavigationLink {
                        LogScreen()
                    } label: {
                        Label("Event log", systemImage: "list.bullet.rectangle")
                    }
                    NavigationLink {
                        Gate1CompareScreen()
                    } label: {
                        Label("Compare Gate-1 staff", systemImage: "rectangle.on.rectangle")
                    }
                }

                Section("Status") {
                    ForEach(statusLines, id: \.self) { line in
                        Text(line)
                            .font(.body.monospaced())
                    }
                }

                Section("Warmup") {
                    Text(warmup.debugLine)
                        .font(.footnote.monospaced())
                    if let report = warmup.report {
                        ForEach(report.lines, id: \.self) { line in
                            Text(line)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                    if case .failed = warmup.state {
                        Button("Retry warmup") { warmup.start() }
                    }
                }

                Section("Run Gate-1") {
                    Button("Run Gate-1 (npy)") { runGate1(png: false) }
                        .disabled(gate1Running)
                    Button("Run Gate-1 (png)") { runGate1(png: true) }
                        .disabled(gate1Running)
                    if gate1Running {
                        Text("running… (\(warmup.debugLine))")
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    if let gate1Verdict {
                        Text(gate1Verdict)
                            .font(.footnote.monospaced())
                            .foregroundStyle(gate1Verdict.contains("PASS") ? .green : .red)
                    }
                    if let gate1Detail {
                        Text(gate1Detail)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Gate-1 parse (staff-only)") {
                    Button("Call parseSheetMusicWithLayout (dummy PNG)") {
                        runDummyParse()
                    }
                    if let lastError {
                        Text(lastError)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.orange)
                    }
                }

                Section("SF2 player") {
                    NavigationLink("Play sample (ode-to-joy.mid, GeneralUser GS)") {
                        PlayerView(route: .sample(SampleMIDI.odeToJoyKey, title: "Ode to Joy (sample)", autoplay: false))
                    }
                    Text(BundledSoundFont.url() == nil ? "GeneralUser-GS.sf2 missing" : "GeneralUser-GS.sf2 bundled")
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                }

                Section("MIDI smoke") {
                    Button("Play empty SMF (structure only)") {
                        playEmptySMF()
                    }
                    Button("Stop") {
                        midiPlayer.stop()
                    }
                    Text(midiPlayer.statusText)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(embedded ? "Model self-test" : "AI Camera - Music Reader")
    }

    /// Waits for the warmup, then runs Gate 1 off the main thread on the warmed sessions.
    private func runGate1(png: Bool) {
        gate1Running = true
        gate1Verdict = nil
        gate1Detail = nil
        Task {
            defer { gate1Running = false }
            do {
                let models = try await warmup.readyModels()
                let result = try await Task.detached(priority: .userInitiated) {
                    try png ? Gate1Runner.runPNG(models: models) : Gate1Runner.runNPY(models: models)
                }.value
                gate1Verdict = "\(result.input): \(result.verdict)"
                gate1Detail = result.detail
                Gate1Runner.record(result)
            } catch {
                gate1Verdict = "ERROR: \(error)"
                Gate1Runner.record(error: error, input: png ? "png" : "npy")
                Gate1Runner.log.error("Gate-1 (\(png ? "png" : "npy", privacy: .public)) error: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func runDummyParse() {
        // Minimal valid 1×1 PNG (not sheet music). Proves linkage only.
        let png = Self.tinyPNG
        do {
            let result = try OMRHomrIOS.parseSheetMusicWithLayout(
                input: ParseSheetMusicInput(imageData: png, staffOnly: true)
            )
            lastError = nil
            statusLines.append(
                "parse OK: midi=\(result.midi.count)B layout=\(result.noteLayout.count) staffs=\(result.staffCount)"
            )
            if !result.midi.isEmpty {
                try? midiPlayer.play(midiData: result.midi)
            }
        } catch let error as OMRError {
            lastError = String(describing: error)
            DiagnosticsLog.shared.record(.warn, .recognition, "dummy parse (staff-only): \(error)", payload: ["kind": "dummy"])
        } catch {
            lastError = "unexpected: \(error)"
            DiagnosticsLog.shared.record(error: error, category: .recognition, context: "dummy parse")
        }
    }

    private func playEmptySMF() {
        let data = SMFWriter().writeEmpty()
        do {
            try midiPlayer.play(midiData: data)
        } catch {
            lastError = "MIDI play failed: \(error)"
            DiagnosticsLog.shared.record(error: error, category: .playback, context: "empty SMF smoke")
        }
    }

    /// Tiny 1×1 opaque PNG — enough non-empty bytes for the API reachability path.
    static let tinyPNG: Data = Data([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
        0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
        0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
        0x00, 0x00, 0x03, 0x00, 0x01, 0x00, 0x05, 0xFE, 0x02, 0xFE, 0x00, 0x00,
        0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ])
}
