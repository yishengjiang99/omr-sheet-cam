import Foundation
import OMRHomrIOS

public enum RecognitionOutcome: Equatable, Sendable {
    /// No recognizer (`StubRecognitionService`, previews / tests only).
    case comingSoon
    /// SMF bytes for the Player plus noteLayout / staffCount / warnings for the compare overlay.
    case recognized(RecognitionDetails)
    case failed(String)

    public var name: String {
        switch self {
        case .comingSoon: return "comingSoon"
        case .recognized: return "recognized"
        case .failed: return "failed"
        }
    }
}

/// Recognition progress event: which phase the scan is in plus its 0...1 fraction.
/// The parse can block on the launch warmup for ~30 s; surfacing that as a "Warming up… x%"
/// phase (instead of a stuck "Reading music… 0%") is the whole point of the phase.
public struct ScanProgress: Sendable, Equatable {
    /// `true` while waiting for / running the model warmup, `false` during the page parse.
    public var warmingUp: Bool
    public var fraction: Double
    /// Seconds of warmup remaining (simple estimate); nil when not warming up or unknown.
    public var etaSeconds: Double? = nil
    /// `true` when this warmup is reloading the models after a memory-warning release (as
    /// opposed to the first load); the UI copy differs ("reloading", not "one-time setup").
    public var isRewarm: Bool = false
}

/// Recognition progress (called from background threads).
public typealias RecognitionProgressHandler = @Sendable (ScanProgress) -> Void

/// Page photo (encoded JPEG / HEIC / PNG bytes; EXIF orientation honored) → MIDI. Implementations run heavy work off the main thread.
public protocol RecognitionService: Sendable {
    func recognize(imageData: Data) async -> RecognitionOutcome
    /// Same, reporting real pipeline progress (0...1, never decreasing). Default: no progress reports.
    func recognize(imageData: Data, progress: @escaping RecognitionProgressHandler) async -> RecognitionOutcome
}

public extension RecognitionService {
    func recognize(imageData: Data, progress: @escaping RecognitionProgressHandler) async -> RecognitionOutcome {
        await recognize(imageData: imageData)
    }
}

/// Scanning-screen progress, updated on the main actor only; never goes down within a phase.
/// A phase change (warming up ⇄ reading) resets the fraction — each phase runs its own 0...100%.
@MainActor
public final class RecognitionProgress: ObservableObject {
    @Published public private(set) var fraction: Double = 0
    @Published public private(set) var warmingUp: Bool = false
    /// Ticking ETA while warming up; nil otherwise.
    @Published public private(set) var etaSeconds: Double?
    /// `true` while the warmup is reloading models after a memory-warning release.
    @Published public private(set) var isRewarm: Bool = false

    public init() {}

    public var percent: Int { Int((fraction * 100).rounded(.down)) }

    public func reset() { fraction = 0; warmingUp = false; etaSeconds = nil; isRewarm = false }

    public func report(_ e: ScanProgress) {
        if e.warmingUp != warmingUp { warmingUp = e.warmingUp; fraction = 0; etaSeconds = nil }
        let v = min(max(e.fraction, 0), 1)
        if v > fraction { fraction = v }
        etaSeconds = e.warmingUp ? e.etaSeconds : nil
        isRewarm = e.isRewarm
    }

    /// Handler for `RecognitionService.recognize(imageData:progress:)`: hops each report to the main actor.
    public nonisolated var handler: RecognitionProgressHandler {
        { [weak self] e in Task { @MainActor in self?.report(e) } }
    }
}

/// Placeholder recognizer (previews / tests); the app uses `PageRecognitionService`.
public struct StubRecognitionService: RecognitionService {
    public func recognize(imageData: Data) async -> RecognitionOutcome { .comingSoon }
}

public extension RecognitionService {
    /// Runs recognition; `nil` when the calling task was cancelled, in which case the result is
    /// discarded: no outcome, Library entry, quota charge or host hand-off. The parse itself cannot be
    /// aborted (ORT), so it still runs to its next checkpoint; only its result is dropped (F6.8).
    func recognizeUnlessCancelled(
        imageData: Data, progress: @escaping RecognitionProgressHandler
    ) async -> RecognitionOutcome? {
        let result = await recognize(imageData: imageData, progress: progress)
        return Task.isCancelled ? nil : result
    }
}
