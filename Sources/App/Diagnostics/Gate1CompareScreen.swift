import OMRHomrIOS
import SwiftUI
import UIKit

/// Diagnostics → "Compare Gate-1 staff": bundled `gate1/staff.png` + its tokens through the same
/// compare / feedback UI as the Result screen, so the flow is testable before full-page parse.
/// Starts with the oracle tokens (`expected.tokens.json`); "Decode on device" swaps in the tokens
/// decoded from staff.png on the warmed sessions.
struct Gate1CompareScreen: View {
    static let captureName = "gate1/staff.png"

    @ObservedObject private var warmup = ModelWarmup.shared
    @State private var image: UIImage?
    @State private var symbols: [EncodedSymbol] = []
    @State private var source = "oracle (expected.tokens.json)"
    @State private var decodeMs: Double = 0
    @State private var loadError: String?
    @State private var decoding = false
    @State private var feedback = OMRFeedback(captureName: Gate1CompareScreen.captureName, staffCount: 1, noteCount: 0)
    @State private var toast: String?

    private var details: RecognitionDetails {
        let notes = RecognizedNote.fromSymbols(symbols)
        return RecognitionDetails(
            midi: Data(), notes: notes, staffCount: max((notes.map(\.staffIndex).max() ?? 0) + 1, 1),
            warnings: [], layoutSource: LayoutSource.midiFallback.rawValue, ms: decodeMs
        )
    }

    var body: some View {
        List {
            if let loadError {
                Section { Text(loadError).foregroundStyle(.red) }
            }
            if let image {
                OMRCompareView(
                    image: image, details: details, captureName: Self.captureName, symbolCount: symbols.count,
                    feedback: $feedback, toast: $toast, showsDeveloperTools: true
                )
            }
            Section("Tokens · \(source)") {
                Button(decoding ? "Decoding… (\(warmup.debugLine))" : "Decode on device (png)") { decode() }
                    .disabled(decoding)
                ForEach(Array(symbols.enumerated()), id: \.offset) { i, s in
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(i)").font(.caption.monospaced()).foregroundStyle(.secondary).frame(width: 28, alignment: .trailing)
                        Text(s.description).font(.caption.monospaced())
                    }
                }
            }
        }
        .navigationTitle("Compare Gate-1 staff")
        .navigationBarTitleDisplayMode(.inline)
        .toast($toast)
        .task { load() }
    }

    private func load() {
        guard image == nil else { return }
        do {
            let dir = try Gate1Runner.bundledFixturesDir()
            guard let img = UIImage(contentsOfFile: dir.appendingPathComponent("staff.png").path) else {
                throw Gate1Runner.RunnerError.fixturesMissing("staff.png unreadable")
            }
            image = img
            symbols = try Gate1Oracle.loadExpectedSymbols(from: dir.appendingPathComponent("expected.tokens.json"))
        } catch {
            loadError = "Gate-1 fixture unavailable: \(error)"
            DiagnosticsLog.shared.record(error: error, category: .gate1, context: "Compare Gate-1 load")
        }
    }

    private func decode() {
        decoding = true
        Task {
            defer { decoding = false }
            do {
                let models = try await warmup.readyModels()
                let result = try await Task.detached(priority: .userInitiated) { try Gate1Runner.runPNG(models: models) }.value
                Gate1Runner.record(result)
                symbols = result.symbols
                decodeMs = result.decodeMs
                source = "decoded on device · \(result.verdict)"
                feedback.wrongNotes.removeAll()
            } catch {
                Gate1Runner.record(error: error, input: "png")
                toast = "Decode failed: \(error)"
            }
        }
    }
}
