import SwiftUI

/// Captured / picked page: saves it to Documents/captures, runs `AppServices.recognition`
/// (stub → "Recognition coming soon"), pushes the Player when MIDI comes back.
struct ResultScreen: View {
    let photo: CapturedPhoto
    var service: any RecognitionService = AppServices.recognition
    var openPlayer: (PlayerRoute) -> Void

    @State private var savedURL: URL?
    @State private var saveError: String?
    @State private var outcome: RecognitionOutcome?
    @State private var sampleError: String?

    var body: some View {
        List {
            Section {
                Image(uiImage: photo.image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .listRowInsets(EdgeInsets())
            }
            Section("Recognition") {
                switch outcome {
                case nil:
                    HStack { ProgressView(); Text("Reading…") }
                case .comingSoon:
                    Label("Recognition coming soon", systemImage: "hourglass")
                    Text("Full-page reading is being built. Your photo is saved for later.")
                        .font(.footnote).foregroundStyle(.secondary)
                case .midi:
                    Label("Recognized", systemImage: "music.note")
                case let .failed(msg):
                    Label("Could not read this page", systemImage: "exclamationmark.triangle")
                    Text(msg).font(.footnote).foregroundStyle(.secondary)
                }
                Button("Play sample") { playSample() }
                if let sampleError { Text(sampleError).font(.footnote).foregroundStyle(.red) }
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
        .task(id: photo.id) { await process() }
    }

    private func process() async {
        guard outcome == nil else { return }
        let image = photo.image
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
        case let .failure(e):
            saveError = "Save failed: \(e)"
            jpeg = image.jpegData(compressionQuality: 0.9) ?? Data()
        }
        let result = await service.recognize(imageData: jpeg)
        outcome = result
        if case let .midi(data) = result { openPlayer(PlayerRoute(midi: data, title: "Your music")) }
    }

    private func playSample() {
        do {
            openPlayer(PlayerRoute(midi: try SampleMIDI.cMajorScale(), title: "Sample: C major scale"))
            sampleError = nil
        } catch {
            sampleError = "Sample unavailable: \(error)"
        }
    }
}
