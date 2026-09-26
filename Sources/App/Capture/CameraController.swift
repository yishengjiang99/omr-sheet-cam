import AVFoundation
import Combine
import UIKit
import os

/// AVFoundation capture: back wide camera, `.photo` preset, full-resolution `AVCapturePhotoOutput`.
/// All session configuration / start / stop / device locking runs on `sessionQueue` (serial),
/// never on the main thread. Published state is updated on the main thread.
final class CameraController: NSObject, ObservableObject, @unchecked Sendable {
    enum Authorization: Equatable { case notDetermined, authorized, denied, restricted }

    @Published private(set) var authorization: Authorization = CameraController.currentAuthorization()
    /// false on the simulator / devices without a back wide camera.
    @Published private(set) var isCameraAvailable = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    @Published private(set) var isRunning = false
    @Published private(set) var torchAvailable = false
    @Published private(set) var torchOn = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var isCapturing = false

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.ragnus.vp.camera.session")
    private let photoOutput = AVCapturePhotoOutput()
    private var device: AVCaptureDevice?
    private var configured = false
    private var wantsRunning = false
    private var inFlight: [Int64: PhotoDelegate] = [:]
    private var observers: [NSObjectProtocol] = []
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.ragnus.vp", category: "camera")

    override init() {
        super.init()
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil) { [weak self] note in
            let reason = (note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int)
                .flatMap(AVCaptureSession.InterruptionReason.init(rawValue:))
            self?.publish { $0.statusMessage = CameraController.message(for: reason) }
        })
        observers.append(nc.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: nil) { [weak self] _ in
            self?.publish { $0.statusMessage = nil }
        })
        observers.append(nc.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { [weak self] note in
            guard let self else { return }
            let error = note.userInfo?[AVCaptureSessionErrorKey] as? AVError
            self.log.error("capture runtime error: \(String(describing: error), privacy: .public)")
            self.sessionQueue.async {
                // Media services reset: restart if we still want to run.
                if error?.code == .mediaServicesWereReset, self.wantsRunning, !self.session.isRunning {
                    self.session.startRunning()
                }
                let running = self.session.isRunning
                self.publish {
                    $0.isRunning = running
                    $0.statusMessage = running ? nil : "Camera error: \(error?.localizedDescription ?? "unknown")"
                }
            }
        })
    }

    deinit { for o in observers { NotificationCenter.default.removeObserver(o) } }

    static func currentAuthorization() -> Authorization {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        default: return .notDetermined
        }
    }

    static func message(for reason: AVCaptureSession.InterruptionReason?) -> String {
        switch reason {
        case .videoDeviceInUseByAnotherClient: return "Camera in use by another app"
        case .videoDeviceNotAvailableWithMultipleForegroundApps: return "Camera unavailable in Split View"
        case .videoDeviceNotAvailableDueToSystemPressure: return "Camera paused (device too hot)"
        default: return "Camera paused"
        }
    }

    // MARK: - Lifecycle

    /// Requests permission if needed, then configures and starts the session (on `sessionQueue`).
    func start() {
        switch Self.currentAuthorization() {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                self.publish { $0.authorization = granted ? .authorized : .denied }
                if granted { self.startSession() }
            }
        case .authorized:
            publish { $0.authorization = .authorized }
            startSession()
        case let other:
            publish { $0.authorization = other }
        }
    }

    func stop() {
        sessionQueue.async {
            self.wantsRunning = false
            if self.session.isRunning { self.session.stopRunning() }
            self.publish { $0.isRunning = false; $0.torchOn = false }
        }
    }

    private func startSession() {
        sessionQueue.async {
            self.wantsRunning = true
            if !self.configured { self.configure() }
            guard self.configured else { return }
            if !self.session.isRunning { self.session.startRunning() }
            let running = self.session.isRunning
            self.publish { $0.isRunning = running }
        }
    }

    /// Runs on `sessionQueue`.
    private func configure() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            publish { $0.isCameraAvailable = false }
            return
        }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input), session.canAddOutput(photoOutput) else {
                publish { $0.statusMessage = "Camera configuration failed" }
                return
            }
            session.addInput(input)
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .quality
            if let largest = device.activeFormat.supportedMaxPhotoDimensions
                .max(by: { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) }) {
                photoOutput.maxPhotoDimensions = largest
            }
            self.device = device
            configured = true
            let torch = device.hasTorch && device.isTorchAvailable
            publish { $0.torchAvailable = torch }
        } catch {
            log.error("camera input: \(String(describing: error), privacy: .public)")
            publish { $0.statusMessage = "Camera unavailable: \(error.localizedDescription)" }
        }
    }

    // MARK: - Controls

    /// Tap-to-focus/expose at a device point of interest ((0,0) top-left, (1,1) bottom-right, landscape).
    func focus(at devicePoint: CGPoint) {
        sessionQueue.async {
            guard let device = self.device else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.autoFocus) {
                    device.focusPointOfInterest = devicePoint
                    device.focusMode = .autoFocus
                }
                if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.autoExpose) {
                    device.exposurePointOfInterest = devicePoint
                    device.exposureMode = .autoExpose
                }
                device.isSubjectAreaChangeMonitoringEnabled = true
            } catch {
                self.log.error("focus lock: \(String(describing: error), privacy: .public)")
            }
        }
    }

    func setTorch(_ on: Bool) {
        sessionQueue.async {
            guard let device = self.device, device.hasTorch, device.isTorchAvailable else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                if on { try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel) } else { device.torchMode = .off }
                let state = device.torchMode == .on
                self.publish { $0.torchOn = state }
            } catch {
                self.log.error("torch: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Full-resolution still. `rotationAngle` = horizon-level capture angle from the preview's
    /// rotation coordinator. Completion on the main thread with an upright image.
    func capturePhoto(rotationAngle: CGFloat?, completion: @escaping (Result<UIImage, Error>) -> Void) {
        publish { $0.isCapturing = true }
        sessionQueue.async {
            guard self.configured, self.session.isRunning else {
                self.publish { $0.isCapturing = false }
                DispatchQueue.main.async { completion(.failure(CaptureError.notRunning)) }
                return
            }
            if let angle = rotationAngle, let conn = self.photoOutput.connection(with: .video),
               conn.isVideoRotationAngleSupported(angle) {
                conn.videoRotationAngle = angle
            }
            let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            settings.maxPhotoDimensions = self.photoOutput.maxPhotoDimensions
            settings.photoQualityPrioritization = .quality
            let id = settings.uniqueID
            let delegate = PhotoDelegate { [weak self] result in
                self?.sessionQueue.async { self?.inFlight[id] = nil }
                self?.publish { $0.isCapturing = false }
                DispatchQueue.main.async { completion(result) }
            }
            self.inFlight[id] = delegate
            self.photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }

    enum CaptureError: Error, CustomStringConvertible {
        case notRunning, noData
        var description: String {
            switch self {
            case .notRunning: return "camera is not running"
            case .noData: return "no photo data"
            }
        }
    }

    private func publish(_ update: @escaping (CameraController) -> Void) {
        DispatchQueue.main.async { [weak self] in
            if let self { update(self) }
        }
    }
}

private final class PhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let done: (Result<UIImage, Error>) -> Void
    init(done: @escaping (Result<UIImage, Error>) -> Void) { self.done = done }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error { return done(.failure(error)) }
        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            return done(.failure(CameraController.CaptureError.noData))
        }
        done(.success(CaptureStore.normalizedUpright(image)))
    }
}
