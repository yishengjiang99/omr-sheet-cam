import SwiftUI

/// Root flow: Library (playlist) is home with how-it-works art, Camera, and Photos import.
/// Camera is pushed on demand. Scan → Reading/Result → Player. Settings is a sheet.
struct RootFlowView: View {
    enum Route: Hashable {
        case camera
        case result(CapturedPhoto)
        case player(PlayerRoute)
    }

    @State private var path: [Route] = Self.initialPath()
    @State private var showSettings = Self.initialSettings()
    @EnvironmentObject private var playback: PlaybackController
    @StateObject private var storeKit = StoreKitManager()
    @ObservedObject private var quota = ScanQuota.shared

    var body: some View {
        NavigationStack(path: $path) {
            LibraryScreen(
                onSettings: { showSettings = true },
                onCamera: { path.append(.camera) },
                onPhoto: { handlePhoto($0) },
                onOpenPlayer: { openNowPlaying() },
                onTrySample: { trySample() }
            ) { entry in
                var r = PlayerRoute(entry: entry)
                r.advanceOnFinish = true // playlist mode: keep going at track end
                path.append(.player(r))
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .camera:
                    CameraScreen(
                        onSettings: { showSettings = true },
                        onLibrary: { path.removeAll { $0 == .camera } },
                        onOpenPlayer: { openNowPlaying() },
                        onPhoto: { handlePhoto($0) }
                    )
                    .toolbar(.hidden, for: .navigationBar)
                case let .result(photo):
                    ResultScreen(photo: photo, service: Self.recognition) { path.append(.player($0)) }
                case let .player(p):
                    PlayerDestination.view(for: p)
                }
            }
        }
        .tint(Theme.coral)
        .sheet(isPresented: $showSettings) { SettingsView().environmentObject(playback) }
        .sheet(isPresented: $quota.showPaywall) {
            PaywallView().environmentObject(storeKit)
        }
        .environmentObject(storeKit)
    }

    /// Camera capture, Photos import, and Try sample: same Result/recognition path (quota gated).
    private func handlePhoto(_ photo: CapturedPhoto) {
        if quota.checkAndConsume() {
            // Leave camera if we came from it, then show result.
            path.removeAll { $0 == .camera }
            path.append(.result(photo))
        }
    }

    /// Empty-library "Try sample picture": same Result/recognition flow as a camera or Photos pick.
    private func trySample() {
        Task { @MainActor in
            do {
                let photo = try await SamplePicture.photo()
                DiagnosticsLog.shared.record(.info, .capture, "Try sample picture (library): ode-to-joy.jpg")
                handlePhoto(photo)
            } catch {
                DiagnosticsLog.shared.record(error: error, category: .capture, context: "Try sample picture (library)")
            }
        }
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
