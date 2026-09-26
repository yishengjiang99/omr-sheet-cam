import SwiftUI

/// Captured / picked page: saves it to Documents/captures, runs `AppServices.recognition`
/// (stub → "Recognition coming soon"), then shows the visual compare + accuracy feedback and a
/// Play button for the recognized MIDI. Every step is recorded in `DiagnosticsLog`.
struct ResultScreen: View {
    let photo: CapturedPhoto
    var service: any RecognitionService = AppServices.recognition
    var openPlayer: (PlayerRoute) -> Void

    @State private var savedURL: URL?
    @State private var saveError: String?
    @State private var outcome: RecognitionOutcome?
    @State private var sampleError: String?
    @State private var feedback = OMRFeedback(captureName: "", staffCount: 0, noteCount: 0)
    @State private var toast: String?

    /// Capture file name used to tie log events + feedback together.
    private var captureName: String { savedURL?.lastPathComponent ?? "unsaved-\(photo.id.uuidString.prefix(8))" }

    var body: some View {
        List {
            if case let .recognized(details) = outcome {
                OMRCompareView(
                    image: photo.image, details: details, captureName: captureName,
                    feedback: $feedback, toast: $toast
                )
            } else {
                Section {
                    Image(uiImage: photo.image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .listRowInsets(EdgeInsets())
                }
            }
            Section("Recognition") {
                switch outcome {
                case nil:
                    HStack { ProgressView(); Text("Reading…") }
                case .comingSoon:
                    Label("Recognition coming soon", systemImage: "hourglass")
                    Text("Full-page reading is being built. Your photo is saved for later. Try Diagnostics → Compare Gate-1 staff to preview the compare view.")
                        .font(.footnote).foregroundStyle(.secondary)
                case let .recognized(details):
                    Button {
                        openPlayer(PlayerRoute(midi: details.midi, title: "Your music"))
                    } label: {
                        Label("Play recognized music", systemImage: "play.fill")
                    }
                case let .failed(msg):
                    Label("Could not read this page", systemImage: "exclamationmark.triangle")
                    Text(msg).font(.footnote).foregroundStyle(.secondary)
                }
                Button("Play sample") { playSample() }
                if let sampleError { Text(sampleError).font(.footnote).foregroundStyle(.red) }
                CopyPromptButton(captureName: captureName, feedback: feedback, toast: $toast)
            }
            Section("Saved") {
                if let savedURL {
                    Text("captures/\(savedURL.lastPathComponent)").font(.footnote.monospaced())
                } else if let saveError {
                    Text(saveError).font(.footnote).foregroundStyle(.red)
                } else {
                    Text("saving…").font(.footnote).foregroundStyle(.secondary)
                }
                Text("\(Int(photo.image.size.width))×\(Int(photo.image.size.height)) from \(photo.source.rawValue)")
                    .font(.caption2.monospaced()).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Result")
        .navigationBarTitleDisplayMode(.inline)
        .toast($toast)
        .task(id: photo.id) { await process() }
    }

    private var pixelSize: String {
        let img = photo.image
        if let cg = img.cgImage { return "\(cg.width)x\(cg.height)" }
        return "\(Int(img.size.width * img.scale))x\(Int(img.size.height * img.scale))"
    }

    private func process() async {
        guard outcome == nil else { return }
        let log = DiagnosticsLog.shared
        let image = photo.image
        let source = photo.source.rawValue
        let saved = await Task.detached(priority: .userInitiated) { () -> Result<(URL, Data), Error> in
            Result {
                let url = try CaptureStore.save(image)
                return (url, try Data(contentsOf: url))
            }
        }.value
        let jpeg: Data
        switch saved {
        case let .success((url, data)):
            savedURL = url
            jpeg = data
            log.record(.info, .capture, "saved captures/\(url.lastPathComponent) (\(pixelSize), \(data.count / 1024) KB, \(source))",
                       payload: ["capture": url.lastPathComponent, "bytes": "\(data.count)", "pixels": pixelSize, "source": source])
        case let .failure(e):
            saveError = "Save failed: \(e)"
            jpeg = image.jpegData(compressionQuality: 0.9) ?? Data()
            log.record(error: e, category: .capture, context: "capture save failed", payload: ["pixels": pixelSize, "source": source])
        }
        feedback.captureName = captureName

        let t0 = DispatchTime.now()
        let result = await service.recognize(imageData: jpeg)
        let ms = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000
        outcome = result
        Self.recordRecognition(result, capture: captureName, inputBytes: jpeg.count, pixels: pixelSize, ms: ms)
        if case let .recognized(d) = result {
            feedback.staffCount = d.staffCount
            feedback.noteCount = d.notes.count
            feedback.layoutSource = d.layoutSource
        }
    }

    /// `recognition` event: input size, ms, staffCount, noteCount, warnings, layoutSource, errors.
    static func recordRecognition(
        _ result: RecognitionOutcome, capture: String, inputBytes: Int, pixels: String, ms: Double,
        log: DiagnosticsLog = .shared
    ) {
        var p: [String: String] = [
            "kind": "run", "capture": capture, "input_bytes": "\(inputBytes)", "pixels": pixels,
            "ms": String(format: "%.1f", ms), "outcome": result.name,
        ]
        var msg = "\(capture): \(result.name) · \(pixels) · \(inputBytes / 1024) KB · \(String(format: "%.0f", ms)) ms"
        var level = DiagnosticsEvent.Level.info
        switch result {
        case .comingSoon:
            break
        case let .recognized(d):
            p["staff_count"] = "\(d.staffCount)"
            p["note_count"] = "\(d.notes.count)"
            p["layout_source"] = d.layoutSource
            p["warnings"] = d.warnings.joined(separator: "; ")
            p["parse_ms"] = String(format: "%.1f", d.ms)
            msg += " · staffs \(d.staffCount) · notes \(d.notes.count) · layout \(d.layoutSource)"
            if !d.warnings.isEmpty { msg += " · \(d.warnings.count) warning(s)"; level = .warn }
        case let .failed(error):
            p["error"] = error
            msg += " · \(error)"
            level = .error
        }
        log.record(level, .recognition, msg, payload: p)
    }

    private func playSample() {
        do {
            openPlayer(PlayerRoute(midi: try SampleMIDI.sweden(), title: "Sample: Sweden"))
            sampleError = nil
        } catch {
            sampleError = "Sample unavailable: \(error)"
            DiagnosticsLog.shared.record(error: error, category: .playback, context: "Play sample")
        }
    }
}
