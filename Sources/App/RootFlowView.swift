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
    @ObservedObject private var storeKit = StoreKitManager.shared
    @Environment(\.scenePhase) private var scenePhase
    /// The photo that hit the paywall; re-submitted if the user turns Pro (P3.7).
    @State private var pendingScan = PendingScan<CapturedPhoto>()
    @State private var proToast: String?
    @ObservedObject private var quota = ScanQuota.shared
    /// Set when "Try sample picture" can't load the sample (same message as the Camera screen).
    @State private var sampleError: String?

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
                    ResultScreen(photo: photo, onRetake: { path = Self.pathAfterRetake(path, photo: photo) }, service: Self.recognition) {
                        path.append(.player($0))
                    }
                case let .player(p):
                    PlayerDestination.view(for: p)
                }
            }
        }
        .tint(Theme.coral)
        .sheet(isPresented: $showSettings) { SettingsView().environmentObject(playback) }
        .sheet(isPresented: $quota.showPaywall, onDismiss: resumePendingScan) {
            PaywallView(reason: quota.paywallReason).environmentObject(storeKit)
        }
        .alert("Couldn't open the sample", isPresented: Binding(get: { sampleError != nil }, set: { if !$0 { sampleError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(sampleError ?? "")
        }
        .environmentObject(storeKit)
        .toast($proToast)
        .onChange(of: storeKit.isPro) { wasPro, isPro in
            proToast = ProConfirmation.message(wasPro: wasPro, isPro: isPro)
        }
        .onChange(of: scenePhase) { _, phase in
            // Expiry, renewal or refund can happen while the app stays alive in the background.
            if phase == .active {
                quota.refreshRemaining() // day rollover
                Task { await refreshThenConsiderReturnReminder() }
            }
        }
        // scenePhase's first value (cold start) does not fire onChange.
        .task { await refreshThenConsiderReturnReminder() }
    }

    /// Refresh first so lapsed/Pro state is right before deciding whether to show the return banner (P2.9).
    private func refreshThenConsiderReturnReminder() async {
        await storeKit.refreshEntitlements()
        ReturnReminder.shared.appBecameActive(quota: quota, purchaseInFlight: storeKit.purchaseInFlight)
    }

    /// Camera capture, Photos import, and Try sample: same Result/recognition path (quota gated).
    private func handlePhoto(_ photo: CapturedPhoto) {
        Task { @MainActor in
            // Re-check Pro against the store first (P7.4), then check quota (charged on success, P1.4).
            guard await quota.admitScan() else {
                pendingScan.hold(photo) // paywall is up: keep the photo for after a purchase
                return
            }
            // Leave camera if we came from it, then show result.
            path.removeAll { $0 == .camera }
            path.append(.result(photo))
        }
    }

    /// Retake from the Result screen: drop it (and anything above it); a camera photo returns to the
    /// live Camera, Photos / sample picks return to the Library (F5.5).
    static func pathAfterRetake(_ path: [Route], photo: CapturedPhoto) -> [Route] {
        var p = path
        if let i = p.firstIndex(of: .result(photo)) { p.removeSubrange(i...) }
        if photo.source == .camera { p.append(.camera) }
        return p
    }

    /// Paywall closed: if the user is now Pro, continue with the photo that triggered it.
    private func resumePendingScan() {
        if let photo = pendingScan.take(isPro: storeKit.isPro) { handlePhoto(photo) }
    }

    /// Empty-library "Try sample picture": same Result/recognition flow as a camera or Photos pick.
    private func trySample() {
        Task { @MainActor in
            let result = await SamplePicture.loadForUser(context: "Try sample picture (library)")
            if let photo = result.photo {
                handlePhoto(photo)
            } else {
                sampleError = result.error
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
