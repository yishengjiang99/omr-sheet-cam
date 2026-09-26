import Combine
import Foundation

/// General MIDI instruments offered in Settings / Player (bank 0 programs in GeneralUser GS).
struct Instrument: Hashable, Identifiable, Sendable {
    /// nil = the file's own instruments.
    var program: Int?
    var name: String
    var id: Int { program ?? -1 }

    static let original = Instrument(program: nil, name: "Original")
    static let all: [Instrument] = [
        original,
        Instrument(program: 0, name: "Piano"),
        Instrument(program: 4, name: "Electric piano"),
        Instrument(program: 6, name: "Harpsichord"),
        Instrument(program: 10, name: "Music box"),
        Instrument(program: 11, name: "Vibraphone"),
        Instrument(program: 19, name: "Organ"),
        Instrument(program: 24, name: "Guitar"),
        Instrument(program: 40, name: "Violin"),
        Instrument(program: 48, name: "Strings"),
        Instrument(program: 52, name: "Choir"),
        Instrument(program: 73, name: "Flute"),
    ]

    static func named(program: Int?) -> Instrument {
        all.first { $0.program == program } ?? Instrument(program: program, name: program.map { "Program \($0)" } ?? "Original")
    }
}

/// Persisted playback preferences (UserDefaults). Shared by Settings and the Player chips.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings(defaults: .standard)

    static let tempoChoices: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    enum Key {
        static let program = "playback.program"   // Int, -1 = original
        static let tempo = "playback.tempo"       // Double
    }

    let defaults: UserDefaults

    @Published var instrument: Instrument {
        didSet { defaults.set(instrument.program ?? -1, forKey: Key.program) }
    }

    @Published var tempo: Double {
        didSet {
            let c = min(2, max(0.5, tempo.isFinite ? tempo : 1))
            if c != tempo { tempo = c; return }
            defaults.set(tempo, forKey: Key.tempo)
        }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        let p = defaults.object(forKey: Key.program) as? Int ?? 0 // default: Piano
        instrument = Instrument.named(program: p < 0 ? nil : p)
        let t = defaults.object(forKey: Key.tempo) as? Double ?? 1
        tempo = min(2, max(0.5, t))
    }

    static func tempoLabel(_ t: Double) -> String {
        let tenths = (t * 10).rounded()
        return abs(t * 10 - tenths) < 1e-9 ? String(format: "%.1f×", t) : String(format: "%.2f×", t)
    }
}

/// Hidden Developer section: tap the Version row `requiredTaps` times (each within `window` s of
/// the previous) to unlock. Persisted in UserDefaults.
@MainActor
final class DeveloperMode: ObservableObject {
    static let shared = DeveloperMode(defaults: .standard)
    static let key = "developerMode.enabled"
    static let requiredTaps = 5

    let defaults: UserDefaults
    let window: TimeInterval
    @Published private(set) var isEnabled: Bool
    private(set) var tapCount = 0
    private var lastTap: Date?

    init(defaults: UserDefaults, window: TimeInterval = 2.0) {
        self.defaults = defaults
        self.window = window
        isEnabled = defaults.bool(forKey: Self.key)
    }

    /// Returns true on the tap that unlocks developer mode.
    @discardableResult
    func registerVersionTap(at now: Date = Date()) -> Bool {
        guard !isEnabled else { return false }
        if let lastTap, now.timeIntervalSince(lastTap) > window { tapCount = 0 }
        lastTap = now
        tapCount += 1
        guard tapCount >= Self.requiredTaps else { return false }
        setEnabled(true)
        return true
    }

    /// Taps left before unlocking (for a "n more taps" hint).
    var tapsRemaining: Int { isEnabled ? 0 : max(0, Self.requiredTaps - tapCount) }

    func setEnabled(_ on: Bool) {
        isEnabled = on
        tapCount = 0
        lastTap = nil
        defaults.set(on, forKey: Self.key)
        DiagnosticsLog.shared.record(.info, .app, "developer mode \(on ? "on" : "off")", payload: ["kind": "developer_mode", "enabled": on ? "1" : "0"])
    }
}
