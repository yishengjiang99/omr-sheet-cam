import SwiftUI

/// Root flow (redesign, no tab bar): Scan is home; Library and Player are pushed from it and
/// Settings is a sheet. Scan → Reading/Result → Player. Developer tools live in Settings behind
/// the hidden Developer section.
struct RootFlowView: View {
    enum Route: Hashable {
        case result(CapturedPhoto)
        case player(PlayerRoute)
        case library
    }

    @State private var path: [Route] = Self.initialPath()
    @State private var showSettings = Self.initialSettings()
    @EnvironmentObject private var playback: PlaybackController

    var body: some View {
        NavigationStack(path: $path) {
            CameraScreen(
                onSettings: { showSettings = true },
                onLibrary: { path.append(.library) },
                onOpenPlayer: { openNowPlaying() },
                onPhoto: { photo in path.append(.result(photo)) }
            )
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case let .result(photo):
                    ResultScreen(photo: photo, service: Self.recognition) { path.append(.player($0)) }
                case let .player(p):
                    PlayerDestination.view(for: p)
                case .library:
                    LibraryScreen(onOpenPlayer: { openNowPlaying() }) { entry in
                        path.append(.player(PlayerRoute(entry: entry)))
                    }
                }
            }
        }
        .tint(Theme.coral)
        .sheet(isPresented: $showSettings) { SettingsView().environmentObject(playback) }
    }

    /// Mini-player tap: show the Player on whatever is loaded (without reloading it).
    private func openNowPlaying() {
        guard let current = playback.current else { return }
        var r = current
        r.autoplay = false
        path.append(.player(r))
    }

    private static func initialSettings() -> Bool {
        #if DEBUG
        return ScreenshotDemo.route == "settings"
        #else
        return false
        #endif
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
