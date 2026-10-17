import Foundation

/// What the "N scans left today" counter shows. TODO: stub (legacy behaviour: nothing is shown).
struct ScansLeftDisplay: Equatable {
    let text: String
    /// Compact form for the camera top bar.
    let shortText: String
    /// True when 2 or fewer scans remain: the label becomes a soft path to Pro.
    let isTappable: Bool
}

enum ScansLeft {
    static let nudgeThreshold = 2

    static func display(remaining: Int?, isPro: Bool) -> ScansLeftDisplay? { nil }
}
