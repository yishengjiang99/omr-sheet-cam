import AVFoundation
import PhotosUI
import SwiftUI

/// Root capture screen: live camera (when available + authorized), tap-to-focus, torch, shutter,
/// and "Choose from Photos". Hands an upright `CapturedPhoto` to `onPhoto`.
struct CameraScreen: View {
    var onPhoto: (CapturedPhoto) -> Void

    @StateObject private var camera = CameraController()
    @State private var rotation = PreviewRotation()
    @State private var focusPoint: CGPoint?
    @State private var pickerItem: PhotosPickerItem?
    @State private var loadingPick = false
    @State private var error: String?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
            VStack {
                if let msg = camera.statusMessage ?? error {
                    Text(msg)
                        .font(.footnote)
                        .padding(8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.top, 8)
                }
                Spacer()
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

    private var controls: some View {
        HStack(alignment: .center) {
            PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                Group {
                    if cameraLive {
                        Label("Choose from Photos", systemImage: "photo.on.rectangle").labelStyle(.iconOnly)
                    } else {
                        Label("Choose from Photos", systemImage: "photo.on.rectangle")
                    }
                }
                    .font(.title3)
                    .padding(12)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .disabled(loadingPick)
            if cameraLive {
                Spacer()
                Button(action: shoot) {
                    Circle()
                        .strokeBorder(.white, lineWidth: 4)
                        .background(Circle().fill(camera.isCapturing ? .gray : .white).padding(6))
                        .frame(width: 76, height: 76)
                }
                .disabled(camera.isCapturing || !camera.isRunning)
                .accessibilityLabel("Shutter")
                Spacer()
                if camera.torchAvailable {
                    Button { camera.setTorch(!camera.torchOn) } label: {
                        Image(systemName: camera.torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                            .font(.title3)
                            .padding(12)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel("Torch")
                } else {
                    Color.clear.frame(width: 48, height: 48)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .foregroundStyle(.white)
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
            case let .failure(e): error = "Capture failed: \(e)"
            }
        }
    }

    private func loadPicked(_ item: PhotosPickerItem) {
        loadingPick = true
        error = nil
        Task {
            defer { loadingPick = false; pickerItem = nil }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    error = "Could not load that photo"
                    return
                }
                let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                    UIImage(data: data).map(CaptureStore.normalizedUpright)
                }.value
                guard let image else {
                    error = "Unsupported image"
                    return
                }
                onPhoto(CapturedPhoto(image: image, source: .library))
            } catch {
                self.error = "Could not load that photo: \(error.localizedDescription)"
            }
        }
    }
}
