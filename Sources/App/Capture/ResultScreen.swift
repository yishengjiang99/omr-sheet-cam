import SwiftUI

/// Captured / picked page (redesign 02-reading → 03-result): saves it to Documents/captures and
/// shows the Reading progress screen while `AppServices.recognition` runs, then "Ready to play" (or "Couldn't read this page" with Try again):
/// editable title, the visual compare + feedback, and a pinned coral Play button (always visible
/// above the home indicator) with "Save to Library". A recognized scan's MIDI is saved to the
/// Library right away. Every step is recorded in `DiagnosticsLog`.
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
    /// Playlist entry for this scan once saved (auto on success, retried by the Play button).
    @State private var playlistEntry: PlaylistEntry?
    @State private var playlistError: String?
    /// Saved capture bytes (reused by Try again) and the attempt counter that re-runs `.task`.
    @State private var input: Data?
    @State private var attempt = 0
    @State private var titleText = ""
    @State private var savedToLibrary = false
    /// Brightness / contrast / size of the photo, measured only when a scan fails (tips).
    @State private var photoQuality: PhotoQuality?
    /// Real pipeline progress for the Reading screen (main actor).
    @StateObject private var progress = RecognitionProgress()
    @Environment(\.dismiss) private var dismiss

    /// "Recognition coming soon" row: plain text, no glyph (nil = no icon; any value must be a valid SF Symbol).
    static let comingSoonTitle = "Recognition coming soon"
    static let comingSoonSymbol: String? = nil

    /// Pinned bottom actions for an outcome; the view renders exactly these.
    enum PinnedAction: String { case play, saveToLibrary }

    static func pinnedActions(for outcome: RecognitionOutcome?) -> [PinnedAction] {
        if case .recognized = outcome { return [.play, .saveToLibrary] }
        return []
    }

    /// "Found 4 staves · 52 notes · about 0:24".
    static func summary(_ d: RecognitionDetails, duration: Double?) -> String {
        var parts = ["Found \(d.staffCount) stave\(d.staffCount == 1 ? "" : "s")", "\(d.notes.count) note\(d.notes.count == 1 ? "" : "s")"]
        if let duration, duration > 0 { parts.append("about \(PlayerView.clock(duration))") }
        return parts.joined(separator: " · ")
    }

    /// Capture file name used to tie log events + feedback together.
    private var captureName: String { savedURL?.lastPathComponent ?? "unsaved-\(photo.id.uuidString.prefix(8))" }

    var body: some View {
        Group {
            if outcome == nil {
                ReadingView(image: photo.image, fraction: progress.fraction, warmingUp: progress.warmingUp, etaSeconds: progress.etaSeconds) { dismiss() }
            } else {
                resultList
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(outcome == nil ? .hidden : .visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    HStack(spacing: 4) { Image(systemName: "chevron.left"); Text("Retake") }
                }
                .accessibilityIdentifier("result.retake")
            }
            ToolbarItem(placement: .topBarTrailing) {
                if let url = playlistEntry?.fileName.map({ PlaylistStore.shared.directory.appendingPathComponent($0) }) {
                    ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                        .accessibilityLabel("Share MIDI")
                }
            }
        }
        .navigationTitle(Self.pinnedActions(for: outcome).isEmpty ? "Result" : "Ready to play")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if case let .recognized(details) = outcome {
                pinnedBar(details)
            }
        }
        .toast($toast)
        .task(id: attempt) { await process() }
    }

    private var resultList: some View {
        List {
            if case let .recognized(details) = outcome {
                Section {
                    HStack {
                        TextField("Title", text: $titleText)
                            .font(.title3.weight(.semibold))
                            .submitLabel(.done)
                            .onSubmit { renameScan() }
                            .accessibilityIdentifier("result.title")
                        Image(systemName: "pencil").foregroundStyle(.secondary)
                    }
                    Label(Self.summary(details, duration: playlistEntry?.duration), systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .symbolRenderingMode(.multicolor)
                    if let playlistError { Text(playlistError).font(.footnote).foregroundStyle(.red) }
                }
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
                Section("Recognition") {
                    switch outcome {
                    case .failed(let msg):
                        let reason = ScanFailure.classify(msg)
                        Label(reason.title, systemImage: "exclamationmark.triangle")
                            .font(.headline)
                            .foregroundStyle(.orange)
                            .accessibilityIdentifier("result.error")
                        Text(reason.explanation)
                            .font(.subheadline).foregroundStyle(.secondary)
                            .accessibilityIdentifier("result.errorExplanation")
                        ForEach(reason.tips(quality: photoQuality)) { tip in
                            Label {
                                Text(tip.text).font(.footnote)
                            } icon: {
                                Image(systemName: tip.symbol).foregroundStyle(Theme.coral)
                            }
                            .accessibilityIdentifier("result.tip")
                        }
                        if reason.isPhotoProblem {
                            Button { dismiss() } label: { Label("Retake photo", systemImage: "camera") }
                                .accessibilityIdentifier("result.retakeFromError")
                        }
                        Button { retry() } label: { Label(reason.isPhotoProblem ? "Try this photo again" : "Try again", systemImage: "arrow.clockwise") }
                            .accessibilityIdentifier("result.retry")
                        DisclosureGroup("Details") {
                            Text(msg).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    default:
                        if let symbol = Self.comingSoonSymbol {
                            Label(Self.comingSoonTitle, systemImage: symbol)
                        } else {
                            Text(Self.comingSoonTitle).font(.headline)
                        }
                        Text("Your photo is saved on this iPhone. Meanwhile, try a sample song.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Button { playSample() } label: { Label("Play a sample", systemImage: "play.circle") }
                    if let sampleError { Text(sampleError).font(.footnote).foregroundStyle(.red) }
                }
            }
            Section {
                if savedURL != nil {
                    Label("Photo saved on this iPhone", systemImage: "checkmark.circle").font(.footnote).foregroundStyle(.secondary)
                } else if let saveError {
                    Text(saveError).font(.footnote).foregroundStyle(.red)
                }
            }
        }
    }

    private func pinnedBar(_ details: RecognitionDetails) -> some View {
        VStack(spacing: 6) {
            ForEach(Self.pinnedActions(for: outcome), id: \.self) { action in
                switch action {
                case .play:
                    PinnedPlayButton { playScan(details) }
                case .saveToLibrary:
                    Button { saveToLibrary(details) } label: {
                        Label(savedToLibrary ? "Saved to Library" : "Save to Library",
                              systemImage: savedToLibrary ? "checkmark.circle.fill" : "tray.and.arrow.down")
                            .font(.subheadline.weight(.semibold))
                    }
                    .tint(Theme.coral)
                    .disabled(savedToLibrary)
                    .accessibilityIdentifier("result.saveToLibrary")
                }
            }
        }
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private var pixelSize: String {
        let img = photo.image
        if let cg = img.cgImage { return "\(cg.width)x\(cg.height)" }
        return "\(Int(img.size.width * img.scale))x\(Int(img.size.height * img.scale))"
    }

    private func retry() {
        DiagnosticsLog.shared.record(.info, .recognition, "\(captureName): try again", payload: ["kind": "retry", "capture": captureName])
        outcome = nil
        attempt += 1
    }

    private func process() async {
        guard outcome == nil else { return }
        let jpeg: Data
        if let input {
            jpeg = input
        } else {
            jpeg = await saveCapture()
            input = jpeg
        }
        await recognize(jpeg)
    }

    /// Saves the upright JPEG to Documents/captures; returns its bytes (in-memory JPEG if saving failed).
    private func saveCapture() async -> Data {
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
        return jpeg
    }

    private func recognize(_ jpeg: Data) async {
        let t0 = DispatchTime.now()
        progress.reset()
        let result = await service.recognize(imageData: jpeg, progress: progress.handler)
        let ms = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000
        if case .failed = result, photoQuality == nil {
            let image = photo.image
            photoQuality = await Task.detached(priority: .userInitiated) { PhotoQuality.measure(image) }.value
        }
        outcome = result
        Self.recordRecognition(result, capture: captureName, inputBytes: jpeg.count, pixels: pixelSize, ms: ms, quality: photoQuality)
        if case let .recognized(d) = result {
            feedback.staffCount = d.staffCount
            feedback.noteCount = d.notes.count
            feedback.layoutSource = d.layoutSource
            saveToPlaylist(d)
        }
    }

    /// Every successful scan goes into the playlist (Application Support/playlist). Idempotent.
    @discardableResult
    private func saveToPlaylist(_ d: RecognitionDetails) -> PlaylistEntry? {
        if let playlistEntry { return playlistEntry }
        do {
            let name = savedURL?.lastPathComponent
            let px = Self.pixelDimensions(photo.image)
            let layout = ScanLayout(d, imageWidth: px.width, imageHeight: px.height, captureName: name)
            let e = try PlaylistStore.shared.addScan(midi: d.midi, captureName: name, layout: layout)
            playlistEntry = e
            if titleText.isEmpty { titleText = e.title }
            playlistError = nil
            return e
        } catch {
            playlistError = "Could not save to playlist: \(error)"
            DiagnosticsLog.shared.record(error: error, category: .playback, context: "playlist save", payload: ["capture": captureName])
            return nil
        }
    }

    /// Upright pixel size of the recognized photo (the note boxes' coordinate space).
    nonisolated static func pixelDimensions(_ image: UIImage) -> (width: Int, height: Int) {
        if let cg = image.cgImage, image.imageOrientation == .up { return (cg.width, cg.height) }
        return (Int((image.size.width * image.scale).rounded()), Int((image.size.height * image.scale).rounded()))
    }

    /// Title field edits apply to the Library entry.
    private func renameScan() {
        guard let e = playlistEntry, titleText != e.title else { return }
        do {
            playlistEntry = try PlaylistStore.shared.rename(e, to: titleText)
        } catch {
            DiagnosticsLog.shared.record(error: error, category: .playback, context: "rename scan")
        }
    }

    /// "Save to Library": the scan is already saved; this confirms it under the edited title.
    private func saveToLibrary(_ d: RecognitionDetails) {
        guard saveToPlaylist(d) != nil else { toast = "Could not save to Library"; return }
        renameScan()
        savedToLibrary = true
        toast = "Saved to Library"
    }

    /// Pinned Play: make sure the scan is in the Library, then open the Player on it.
    private func playScan(_ d: RecognitionDetails) {
        renameScan()
        if let e = saveToPlaylist(d) {
            openPlayer(PlayerRoute(entry: e))
        } else {
            openPlayer(PlayerRoute(midi: d.midi, title: "Your music"))
        }
    }

    /// `recognition` event: input size, ms, staffCount, noteCount, warnings, layoutSource, errors.
    static func recordRecognition(
        _ result: RecognitionOutcome, capture: String, inputBytes: Int, pixels: String, ms: Double,
        quality: PhotoQuality? = nil, log: DiagnosticsLog = .shared
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
            let reason = ScanFailure.classify(error)
            p["error"] = error
            p["failure_reason"] = reason.title
            if let q = quality {
                p["photo_mean_luma"] = String(format: "%.0f", q.meanLuma)
                p["photo_luma_std"] = String(format: "%.0f", q.lumaStdDev)
            }
            msg += " · \(reason.title) · \(error)"
            level = .error
        }
        log.record(level, .recognition, msg, payload: p)
    }

    private func playSample() {
        do {
            guard let e = PlaylistStore.shared.entry(id: "sample:\(SampleMIDI.odeToJoyKey)") else { throw SampleMIDI.SampleError.missing("ode-to-joy.mid") }
            openPlayer(PlayerRoute(entry: e))
            sampleError = nil
        } catch {
            sampleError = "Sample unavailable: \(error)"
            DiagnosticsLog.shared.record(error: error, category: .playback, context: "Play sample")
        }
    }
}

/// Accent-filled Play button pinned above the home indicator with a subtle pulse (off with
/// Reduce Motion).
struct PinnedPlayButton: View {
    var action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        Button(action: action) {
            Label("Play", systemImage: "play.fill")
                .font(.title3.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
        }
        .buttonStyle(CoralButtonStyle())
        .shadow(color: Theme.coral.opacity(pulse ? 0.55 : 0.2), radius: pulse ? 18 : 8)
        .scaleEffect(pulse ? 1.02 : 1)
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .accessibilityIdentifier("result.play")
        .accessibilityHint("Adds this scan to your Library and plays it")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}
