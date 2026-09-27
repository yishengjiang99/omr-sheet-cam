import AVFoundation
import Photos
import PhotosUI
import SwiftUI

/// Scan (home, redesign 01-scan): live camera (when available + authorized), tap-to-focus,
/// Settings (gear) and torch on top, Photos · shutter · Library at the bottom. Hands an upright
/// `CapturedPhoto` to `onPhoto`. The app-wide mini-player shows above the controls while
/// something is loaded.
struct CameraScreen: View {
    var onSettings: () -> Void = {}
    var onLibrary: () -> Void = {}
    var onOpenPlayer: () -> Void = {}
    var onPhoto: (CapturedPhoto) -> Void

    @StateObject private var camera = CameraController()
    @State private var rotation = PreviewRotation()
    @State private var focusPoint: CGPoint?
    @State private var pickerItem: PhotosPickerItem?
    @State private var loadingPick = false
    @State private var error: String?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var playback: PlaybackController

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
            VStack {
                topBar
                Spacer()
                if cameraLive {
                    Text("Hold steady over one page")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(.black.opacity(0.35), in: Capsule())
                        .padding(.bottom, 12)
                }
                if playback.current != nil {
                    MiniPlayer(controller: playback, onOpen: onOpenPlayer)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                        .environment(\.colorScheme, .light)
                }
                controls
            }
        }
        .onAppear { if camera.isCameraAvailable { camera.start() } }
        .onDisappear { camera.stop() }
        .onChange(of: scenePhase) { _, phase in
            guard camera.isCameraAvailable else { return }
            if phase == .active { camera.start() } else if phase == .background { camera.stop() }
        }
        .onChange(of: camera.isRunning) { _, running in if running { rotation.refresh() } }
        .onChange(of: pickerItem) { _, item in if let item { loadPicked(item) } }
    }

    @ViewBuilder private var content: some View {
        if !camera.isCameraAvailable {
            messageView(
                icon: "camera.fill", title: "Camera unavailable",
                detail: "This device has no camera. Choose a photo of sheet music instead."
            )
        } else {
            switch camera.authorization {
            case .authorized:
                CameraPreviewView(session: camera.session, rotation: rotation) { layerPoint, devicePoint in
                    camera.focus(at: devicePoint)
                    focusPoint = layerPoint
                }
                .ignoresSafeArea()
                .overlay(alignment: .topLeading) { focusIndicator }
            case .notDetermined:
                messageView(icon: "camera", title: "Camera access", detail: "Requesting permission…")
            case .denied:
                VStack(spacing: 12) {
                    messageView(
                        icon: "camera.fill", title: "Camera access denied",
                        detail: "Allow camera access in Settings to photograph sheet music, or choose a photo."
                    )
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .buttonStyle(.borderedProminent)
                }
            case .restricted:
                messageView(
                    icon: "lock.fill", title: "Camera restricted",
                    detail: "Camera access is restricted on this device. Choose a photo instead."
                )
            }
        }
    }

    @ViewBuilder private var focusIndicator: some View {
        if let p = focusPoint {
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.yellow, lineWidth: 2)
                .frame(width: 72, height: 72)
                .position(p)
                .allowsHitTesting(false)
                .task(id: p) {
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    if focusPoint == p { focusPoint = nil }
                }
        }
    }

    private var cameraLive: Bool { camera.isCameraAvailable && camera.authorization == .authorized }

    private var topBar: some View {
        HStack {
            circleButton("gearshape", label: "Settings", action: onSettings)
                .accessibilityIdentifier("scan.settings")
            Spacer()
            if let msg = camera.statusMessage ?? error {
                Text(msg)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(.black.opacity(0.4), in: Capsule())
            }
            Spacer()
            if cameraLive && camera.torchAvailable {
                circleButton(camera.torchOn ? "bolt.fill" : "bolt", label: "Torch") { camera.setTorch(!camera.torchOn) }
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private func circleButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.35), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.25)))
        }
        .accessibilityLabel(label)
    }

    private var controls: some View {
        HStack(alignment: .center) {
            PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                bottomItem(icon: "photo.on.rectangle", title: "Photos")
            }
            .disabled(loadingPick)
            .accessibilityIdentifier("scan.photos")
            Spacer()
            Button(action: shoot) {
                Circle()
                    .strokeBorder(.white, lineWidth: 5)
                    .background(Circle().fill(camera.isCapturing ? .gray : .white).padding(8))
                    .frame(width: 84, height: 84)
            }
            .disabled(!cameraLive || camera.isCapturing || !camera.isRunning)
            .opacity(cameraLive ? 1 : 0.35)
            .accessibilityLabel("Shutter")
            Spacer()
            Button(action: onLibrary) {
                bottomItem(icon: "music.note.list", title: "Library")
            }
            .accessibilityIdentifier("scan.library")
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 20)
        .foregroundStyle(.white)
    }

    private func bottomItem(icon: String, title: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 52, height: 52)
                .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.25)))
            Text(title).font(.caption.weight(.semibold))
        }
        .frame(width: 72)
    }

    private func messageView(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.largeTitle)
            Text(title).font(.headline)
            Text(detail).font(.subheadline).multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
        .foregroundStyle(.white)
        .padding(32)
    }

    private func shoot() {
        error = nil
        camera.capturePhoto(rotationAngle: rotation.captureAngle) { result in
            switch result {
            case let .success(image): onPhoto(CapturedPhoto(image: image, source: .camera))
            case let .failure(e):
                error = "Capture failed: \(e)"
                DiagnosticsLog.shared.record(error: e, category: .capture, context: "photo capture")
            }
        }
    }

    private func loadPicked(_ item: PhotosPickerItem) {
        loadingPick = true
        error = nil
        Task {
            defer { loadingPick = false; pickerItem = nil }
            do {
                guard let data = try await Self.loadPickedData(item) else {
                    error = "Could not load that photo"
                    DiagnosticsLog.shared.record(.error, .capture, "Photos pick: no data")
                    return
                }
                let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                    UIImage(data: data).map(CaptureStore.normalizedUpright)
                }.value
                guard let image else {
                    error = "Unsupported image"
                    DiagnosticsLog.shared.record(.error, .capture, "Photos pick: unsupported image (\(data.count) bytes)")
                    return
                }
                onPhoto(CapturedPhoto(image: image, source: .library))
            } catch {
                self.error = "Could not load that photo: \(error.localizedDescription)"
                DiagnosticsLog.shared.record(error: error, category: .capture, context: "Photos pick")
            }
        }
    }

    /// Photo bytes for a picker item. `loadTransferable(type: Data.self)` throws "does not support
    /// import" for assets that aren't on the device (iCloud-only photos), so fall back to PHAsset
    /// with network access and let those download instead of failing.
    private static func loadPickedData(_ item: PhotosPickerItem) async throws -> Data? {
        do {
            if let data = try await item.loadTransferable(type: Data.self) { return data }
        } catch {
            DiagnosticsLog.shared.record(.info, .capture,
                "Photos pick: transferable failed (\(error.localizedDescription)); trying PHAsset download")
        }
        guard let id = item.itemIdentifier,
              let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else {
            return nil
        }
        return try await withCheckedThrowingContinuation { cont in
            let opts = PHImageRequestOptions()
            opts.isNetworkAccessAllowed = true
            opts.deliveryMode = .highQualityFormat
            opts.version = .current
            var resumed = false
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: opts) { data, _, _, info in
                guard !resumed else { return }
                resumed = true
                if let data { cont.resume(returning: data); return }
                if let err = info?[PHImageErrorKey] as? Error { cont.resume(throwing: err); return }
                let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                cont.resume(throwing: PhotoPickError.noData(cancelled: cancelled))
            }
        }
    }
}

private enum PhotoPickError: Error {
    case noData(cancelled: Bool)
}
