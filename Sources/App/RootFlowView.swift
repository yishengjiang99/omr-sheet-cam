import SwiftUI

/// Root flow: Camera → Result → Player; Playlist → Player. Diagnostics (Gate1RootView) from the toolbar.
struct RootFlowView: View {
    enum Route: Hashable {
        case result(CapturedPhoto)
        case player(PlayerRoute)
        case log
        case playlist
    }

    @State private var path: [Route] = Self.initialPath()
    @State private var showDiagnostics = false

    var body: some View {
        NavigationStack(path: $path) {
            CameraScreen { photo in path.append(.result(photo)) }
                .navigationTitle("AI Camera - Music Reader")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { path.append(.log) } label: { Label("Log", systemImage: "list.bullet.rectangle") }
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button { path.append(.playlist) } label: { Label("Playlist", systemImage: "music.note.list") }
                            .accessibilityIdentifier("camera.playlist")
                        Button("Diagnostics") { showDiagnostics = true }
                    }
                }
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case let .result(photo):
                        ResultScreen(photo: photo, service: Self.recognition) { path.append(.player($0)) }
                    case let .player(p):
                        PlayerDestination.view(for: p)
                    case .log:
                        LogScreen()
                    case .playlist:
                        PlaylistScreen(store: .shared, currentID: nil) { path.append(.player(PlayerRoute(entry: $0))) }
                    }
                }
        }
        .sheet(isPresented: $showDiagnostics) {
            Gate1RootView()
                .overlay(alignment: .topLeading) {
                    Button("Done") { showDiagnostics = false }
                        .padding()
                }
        }
    }

    @MainActor
    private static func initialPath() -> [Route] {
        #if DEBUG
        return ScreenshotDemo.initialPath()
        #else
        return []
        #endif
    }

    private static var recognition: any RecognitionService {
        #if DEBUG
        if ScreenshotDemo.route == "result" { return ScreenshotDemo.Recognition() }
        #endif
        return AppServices.recognition
    }
}
