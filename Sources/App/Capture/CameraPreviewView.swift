import AVFoundation
import SwiftUI
import UIKit

/// Live preview (`AVCaptureVideoPreviewLayer`) with tap-to-focus. Keeps the preview upright via
/// `AVCaptureDevice.RotationCoordinator` and exposes the horizon-level capture angle.
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    let rotation: PreviewRotation
    /// (layer point for the indicator, device point of interest for the camera).
    var onTap: (CGPoint, CGPoint) -> Void

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.onTap = onTap
        rotation.attach(view.previewLayer)
        return view
    }

    func updateUIView(_ view: PreviewUIView, context: Context) {
        view.onTap = onTap
    }

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        var onTap: ((CGPoint, CGPoint) -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .black
            addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) unused") }

        @objc private func tapped(_ g: UITapGestureRecognizer) {
            let p = g.location(in: self)
            onTap?(p, previewLayer.captureDevicePointConverted(fromLayerPoint: p))
        }
    }
}

/// Owns the rotation coordinator (main thread) for preview + capture orientation.
@MainActor
final class PreviewRotation {
    private var coordinator: AVCaptureDevice.RotationCoordinator?
    private var observation: NSKeyValueObservation?
    private weak var layer: AVCaptureVideoPreviewLayer?

    func attach(_ layer: AVCaptureVideoPreviewLayer) {
        self.layer = layer
        guard coordinator == nil,
              let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return }
        let c = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: layer)
        coordinator = c
        apply(c.videoRotationAngleForHorizonLevelPreview)
        observation = c.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.new]) { [weak self] c, _ in
            let angle = c.videoRotationAngleForHorizonLevelPreview
            Task { @MainActor in self?.apply(angle) }
        }
    }

    private func apply(_ angle: CGFloat) {
        guard let conn = layer?.connection, conn.isVideoRotationAngleSupported(angle) else { return }
        conn.videoRotationAngle = angle
    }

    /// Re-applies the preview angle (the layer's connection only exists once the session runs).
    func refresh() {
        if let c = coordinator { apply(c.videoRotationAngleForHorizonLevelPreview) }
    }

    var captureAngle: CGFloat? { coordinator?.videoRotationAngleForHorizonLevelCapture }
}
