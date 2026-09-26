import SwiftUI
import OMRHomrIOS

/// Gate-1 debug surface only — status, warmup, MIDI smoke.
/// No capture camera UI, no geometry overlays, no App Store polish.
struct Gate1RootView: View {
    @State private var statusLines: [String] = [
        "Gate-1 shell",
        "Package: OMRHomrIOS (AGPL)",
        "Scope: staff-only parse → MIDI smoke",
        "Blocked: onnx_checkpoints + C-scale fixtures + ORT bindings",
    ]
    @State private var lastError: String?
    @State private var midiPlayer = SimpleMIDIPlayer()
    @State private var warmupNote: String = SessionWarmup.statusDescription

    var body: some View {
        NavigationStack {
            List {
                Section("Status") {
                    ForEach(statusLines, id: \.self) { line in
                        Text(line)
                            .font(.body.monospaced())
                    }
                }

                Section("Warmup") {
                    Text(warmupNote)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                    Button("Re-run SessionWarmup") {
                        SessionWarmup.warmupAtLaunch()
                        warmupNote = SessionWarmup.statusDescription
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
            .navigationTitle("AI Camera - Music Reader")
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
        } catch {
            lastError = "unexpected: \(error)"
        }
    }

    private func playEmptySMF() {
        let data = SMFWriter().writeEmpty()
        do {
            try midiPlayer.play(midiData: data)
        } catch {
            lastError = "MIDI play failed: \(error)"
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
