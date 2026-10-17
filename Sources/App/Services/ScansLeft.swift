import Foundation

/// What the "N scans left today" counter shows (P1.6). Quiet text for free users; becomes a tappable
/// nudge when 2 or fewer scans remain. Hidden for Pro and while the count is unknown.
struct ScansLeftDisplay: Equatable {
    let text: String
    /// Compact form for the camera top bar.
    let shortText: String
    /// True when 2 or fewer scans remain: the label becomes a soft path to Pro.
    let isTappable: Bool
}

enum ScansLeft {
    static let nudgeThreshold = 2

    static func display(remaining: Int?, isPro: Bool) -> ScansLeftDisplay? {
        guard !isPro, let remaining, remaining >= 0, remaining != Int.max else { return nil }
        let text: String
        switch remaining {
        case 0: text = "0 free scans left - resets tomorrow"
        case 1: text = "1 free scan left today"
        default: text = "\(remaining) free scans left today"
        }
        return ScansLeftDisplay(text: text, shortText: "\(remaining) left", isTappable: remaining <= nudgeThreshold)
    }
}
