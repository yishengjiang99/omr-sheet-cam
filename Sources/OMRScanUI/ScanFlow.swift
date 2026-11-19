import AVFoundation
import OMRScanKit
import PDFKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import VisionKit

/// A page image the host supplies instead of the camera (UI tests: the simulator has no document
/// camera). The host decides when to pass one, e.g. only under its `-uiTestScanFixture` flag.
public struct ScanFixture {
    public var title: String
    public var accessibilityID: String
    public var load: () -> UIImage?

    public init(title: String = "Use test sheet", accessibilityID: String = "scan-fixture", load: @escaping () -> UIImage?) {
        self.title = title; self.accessibilityID = accessibilityID; self.load = load
    }
}

/// Drives `OMRScanFlow`: choose → reading → done / error. Cancel cancels the recognition task, and
/// a cancelled scan never reaches the host (`ScanRunner` guarantees that).
@MainActor
public final class ScanFlowModel: ObservableObject {
    public enum Phase: Equatable {
        case choose, working
        case done(tracks: Int, notes: Int)
        case error(ScanError)
    }

    @Published public var phase: Phase = .choose
    @Published public private(set) var status = ScanStatus(phase: .reading, fraction: 0)
    @Published public private(set) var firstPage: UIImage?

    let runner: ScanRunner
    let host: any ScanHost
    var onClose: (ScanResult?) -> Void
    private var task: Task<Void, Never>?

    public init(host: any ScanHost, runner: ScanRunner = ScanRunner(), onClose: @escaping (ScanResult?) -> Void) {
        self.host = host; self.runner = runner; self.onClose = onClose
    }

    public func fail(_ kind: ScanError.Kind, _ message: String, code: String) {
        phase = .error(ScanError(kind: kind, message: message, reasonCode: code))
    }

    public func scan(_ images: [UIImage], source: ScanSource) {
        guard !images.isEmpty else { return }
        firstPage = images.first
        begin(pageCount: images.count)
        task?.cancel()
        task = Task { [weak self] in
            // Encoding runs off the main thread; the runner then decodes (gray or color) itself.
            let pages = await Task.detached(priority: .userInitiated) { images.compactMap { $0.jpegData(compressionQuality: 0.92) } }.value
            guard !Task.isCancelled else { return }
            await self?.run(pages: pages, source: source)
        }
    }

    /// Scan from pages already encoded as image data. File imports encode incrementally in
    /// `ScanPages.pageData`, so no full-size page images are ever retained on this path.
    public func scan(pageData pages: [Data], source: ScanSource) {
        guard !pages.isEmpty else { return }
        firstPage = pages.first.flatMap { UIImage(data: $0) }
        begin(pageCount: pages.count)
        task?.cancel()
        task = Task { [weak self] in await self?.run(pages: pages, source: source) }
    }

    private func begin(pageCount: Int) {
        status = ScanStatus(phase: .reading, fraction: 0, pageCount: pageCount)
        phase = .working
    }

    private func run(pages: [Data], source: ScanSource) async {
        let runner = runner, host = host
        let post: @Sendable (ScanStatus) -> Void = { [weak self] status in
            Task { @MainActor in self?.apply(status) }
        }
        do {
            let result = try await runner.run(pages: pages, source: source, host: host, onStatus: post)
            guard !Task.isCancelled else { return }
            phase = .done(tracks: result.trackCount, notes: result.noteCount)
            try? await Task.sleep(nanoseconds: 700_000_000)
            if case .done = phase { onClose(result) }
        } catch let e as ScanError {
            guard e.kind != .cancelled, !Task.isCancelled else { return }
            phase = .error(e)
        } catch {
            phase = .error(ScanError(kind: .failed, message: error.localizedDescription, reasonCode: "parse_error"))
        }
    }

    /// Whole-scan status; a phase never moves backward within itself (warming → reading only).
    private func apply(_ s: ScanStatus) {
        guard case .working = phase else { return }
        if s.phase == status.phase, s.fraction < status.fraction { return }
        if status.phase == .reading, s.phase == .warming, status.fraction > 0 { return }
        status = s
    }

    public func cancel() {
        task?.cancel()
        task = nil
        onClose(nil)
    }
}

/// The scan flow, ready to present: choose a source (document camera, photos, PDF / image file,
/// optional fixture) → a determinate "Warming up… x%" / "Reading music… x%" card → result or error.
/// Look comes from the `scanTheme` environment value; copy from `ScanStrings`.
public struct OMRScanFlow: View {
    @StateObject private var model: ScanFlowModel
    private let fixture: ScanFixture?
    @State private var showCamera = false
    @State private var showFile = false
    @State private var photoItems: [PhotosPickerItem] = []
    @Environment(\.scanTheme) private var theme

    public init(host: any ScanHost, runner: ScanRunner = ScanRunner(), fixture: ScanFixture? = nil,
                onClose: @escaping (ScanResult?) -> Void) {
        _model = StateObject(wrappedValue: ScanFlowModel(host: host, runner: runner, onClose: onClose))
        self.fixture = fixture
    }

    /// Presents an existing model (previews, snapshot tests that need a given phase).
    public init(model: ScanFlowModel, fixture: ScanFixture? = nil) {
        _model = StateObject(wrappedValue: model)
        self.fixture = fixture
    }

    public var body: some View {
        Group {
            if case .working = model.phase {
                ReadingView(image: model.firstPage, fraction: model.status.fraction,
                            warmingUp: model.status.phase == .warming, etaSeconds: model.status.etaSeconds,
                            isRewarm: model.status.isRewarm) { model.cancel() }
            } else {
                sheet
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            DocumentCamera { images in
                showCamera = false
                model.scan(images, source: .camera)
            } onCancel: { showCamera = false } onError: { e in
                showCamera = false
                model.fail(.failed, e.localizedDescription, code: "parse_error")
            }.ignoresSafeArea()
        }
        .fileImporter(isPresented: $showFile, allowedContentTypes: [.pdf, .image]) { result in
            switch result {
            case let .success(url):
                Task {
                    // Rasterizing + encoding run on a background task, one page at a time.
                    let pages = await ScanPages.pageData(fromFile: url)
                    if pages.isEmpty { model.fail(.unreadableInput, "the file has no readable pages", code: "invalid_input") }
                    else { model.scan(pageData: pages, source: .file) }
                }
            case let .failure(e): model.fail(.unreadableInput, e.localizedDescription, code: "invalid_input")
            }
        }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                var images: [UIImage] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) { images.append(img) }
                }
                photoItems = []
                if images.isEmpty { model.fail(.unreadableInput, "the selected photo couldn't be opened", code: "invalid_input") }
                else { model.scan(images, source: .photos) }
            }
        }
    }

    private var sheet: some View {
        NavigationStack {
            VStack(spacing: 18) {
                switch model.phase {
                case .choose, .working: choose
                case let .done(tracks, notes):
                    Spacer()
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 48)).foregroundStyle(theme.accent)
                    Text(ScanStrings.format("flow.done", "Added %d track(s) · %d notes", tracks, notes))
                        .foregroundStyle(theme.sheetText)
                    Spacer()
                case let .error(e): errorView(e)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { Rectangle().fill(theme.sheetBackground).ignoresSafeArea() }
            .navigationTitle(ScanStrings.string("flow.title", "Scan sheet music"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ScanStrings.string("reading.cancel", "Cancel")) { model.cancel() }
                }
            }
        }
    }

    private var choose: some View {
        VStack(spacing: 14) {
            Image(systemName: "music.note.list").font(.system(size: 44)).foregroundStyle(theme.accent).padding(.top, 12)
            Text(ScanStrings.string("flow.intro", "Turn printed sheet music into a MIDI file."))
                .multilineTextAlignment(.center).foregroundStyle(theme.sheetSecondaryText)
            Spacer().frame(height: 8)
            optionButton(ScanStrings.string("flow.camera", "Scan with camera"), "doc.viewfinder", "scan-camera") { startCamera() }
            PhotosPicker(selection: $photoItems, maxSelectionCount: 10, matching: .images) {
                optionLabel(ScanStrings.string("flow.photos", "Choose photos"), "photo.on.rectangle")
            }.accessibilityIdentifier("scan-photos")
            optionButton(ScanStrings.string("flow.file", "Import PDF or image"), "doc.richtext", "scan-pdf") { showFile = true }
            if let fixture {
                optionButton(fixture.title, "testtube.2", fixture.accessibilityID) {
                    if let img = fixture.load() { model.scan([img], source: .fixture) }
                }
            }
            Spacer()
        }
    }

    private func errorView(_ e: ScanError) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 44)).foregroundStyle(theme.destructive)
            Text(Self.message(for: e)).multilineTextAlignment(.center).foregroundStyle(theme.sheetText)
                .accessibilityIdentifier("scan-error")
            if e.reasonCode == "camera_denied", let url = URL(string: UIApplication.openSettingsURLString) {
                Link(ScanStrings.string("flow.openSettings", "Open Settings"), destination: url).foregroundStyle(theme.accent)
            }
            Button(ScanStrings.string("flow.retry", "Try again")) { model.phase = .choose }
                .buttonStyle(.borderedProminent).tint(theme.accent)
            Spacer()
        }
    }

    /// User-facing copy for a failed scan, by kind.
    public static func message(for e: ScanError) -> String {
        switch e.kind {
        case .nothingRecognized: return ScanStrings.string("flow.error.nothing", "No notes were recognized. Try a sharper, well-lit photo of printed sheet music.")
        case .recognizerUnavailable: return ScanStrings.format("flow.error.unavailable", "Sheet recognition isn't available: %@", e.message)
        case .unreadableInput: return ScanStrings.format("flow.error.unreadable", "Couldn't read that file: %@", e.message)
        case .cancelled: return ""
        case .handOffFailed: return e.message
        case .failed:
            if e.reasonCode == "camera_denied" { return ScanStrings.string("flow.error.cameraDenied", "Camera access is off. Allow it in Settings, or import a photo or PDF instead.") }
            if e.reasonCode == "gated" { return ScanStrings.string("flow.error.gated", "This scan isn't available right now.") }
            return ScanStrings.format("flow.error.failed", "Recognition failed: %@", e.message)
        }
    }

    private func startCamera() {
        guard VNDocumentCameraViewController.isSupported else {
            model.fail(.failed, "no document camera", code: "no_camera")
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: showCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { ok in
                Task { @MainActor in
                    if ok { showCamera = true } else { model.fail(.failed, "camera denied", code: "camera_denied") }
                }
            }
        default: model.fail(.failed, "camera denied", code: "camera_denied")
        }
    }

    private func optionLabel(_ title: String, _ icon: String) -> some View {
        Label(title, systemImage: icon).font(.headline).frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(theme.sheetText).background(theme.sheetSurface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.sheetBorder))
    }

    private func optionButton(_ title: String, _ icon: String, _ id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { optionLabel(title, icon) }.accessibilityIdentifier(id)
    }
}

/// Page rasterizing for file imports.
public enum ScanPages {
    /// Longest edge, in pixels, of a rendered or imported page. Recognition resizes every page
    /// to the model's 1280×256 input, and a letter/A4 page at 200 dpi is ~1700×2200 px, so
    /// 2560 keeps ordinary pages at full quality while capping oversize ones: a 36×48 in page
    /// at 200 dpi would otherwise rasterize to ~69 MP per page.
    public static let maxLongEdge: CGFloat = 2560

    /// Rasterizes one PDF page at ~200 dpi on white, clamped to `maxLongEdge`.
    /// Returns nil for a missing page or degenerate page bounds.
    public static func renderPage(_ doc: PDFDocument, at index: Int, dpi: CGFloat = 200) -> UIImage? {
        guard let page = doc.page(at: index) else { return nil }
        let box = page.bounds(for: .mediaBox)
        guard box.width > 0, box.height > 0 else { return nil }
        var scale = dpi / 72
        let longEdge = max(box.width, box.height) * scale
        if longEdge > maxLongEdge { scale *= maxLongEdge / longEdge }
        let size = CGSize(width: (box.width * scale).rounded(), height: (box.height * scale).rounded())
        guard size.width >= 1, size.height >= 1 else { return nil }
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            ctx.cgContext.translateBy(x: 0, y: size.height); ctx.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: ctx.cgContext)
        }
    }

    /// Rasterizes up to `maxPages` of a PDF at ~200 dpi on white, each page clamped to
    /// `maxLongEdge`. Prefer `pageData(fromFile:)` for imports: it encodes each page before
    /// rendering the next, so no more than one full-size page image is alive at a time.
    public static func render(_ doc: PDFDocument, maxPages: Int = 10, dpi: CGFloat = 200) -> [UIImage] {
        (0..<min(doc.pageCount, maxPages)).compactMap { renderPage(doc, at: $0, dpi: dpi) }
    }

    /// Downscales an imported image whose long edge exceeds `maxLongEdge`; unchanged otherwise.
    static func clamped(_ image: UIImage) -> UIImage {
        let px = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let longEdge = max(px.width, px.height)
        guard longEdge > maxLongEdge else { return image }
        let f = maxLongEdge / longEdge
        let size = CGSize(width: (px.width * f).rounded(), height: (px.height * f).rounded())
        guard size.width >= 1, size.height >= 1 else { return image }
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: size, format: fmt).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Pages of a picked PDF or image file (security-scoped URL from `fileImporter`).
    public static func images(fromFile url: URL) -> [UIImage] {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if let doc = PDFDocument(url: url) { return render(doc) }
        if let data = try? Data(contentsOf: url), let img = UIImage(data: data) { return [clamped(img)] }
        return []
    }

    /// JPEG pages of a picked PDF or image file, rendered and encoded one page at a time on a
    /// background task, so importing never blocks the main thread and never holds more than one
    /// full-size page image. Empty when the file has no readable pages.
    public static func pageData(fromFile url: URL, maxPages: Int = 10) async -> [Data] {
        await Task.detached(priority: .userInitiated) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let doc = PDFDocument(url: url) {
                return (0..<min(doc.pageCount, maxPages)).compactMap { i in
                    autoreleasepool { renderPage(doc, at: i)?.jpegData(compressionQuality: 0.92) }
                }
            }
            if let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
                return [clamped(img).jpegData(compressionQuality: 0.92)].compactMap { $0 }
            }
            return []
        }.value
    }
}

struct DocumentCamera: UIViewControllerRepresentable {
    var onScan: ([UIImage]) -> Void
    var onCancel: () -> Void
    var onError: (Error) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController(); vc.delegate = context.coordinator; return vc
    }
    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentCamera
        init(_ p: DocumentCamera) { parent = p }
        func documentCameraViewController(_ c: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            parent.onScan((0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
        }
        func documentCameraViewControllerDidCancel(_ c: VNDocumentCameraViewController) { parent.onCancel() }
        func documentCameraViewController(_ c: VNDocumentCameraViewController, didFailWithError e: Error) { parent.onError(e) }
    }
}
