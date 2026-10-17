import Foundation

/// Quiet "Go Pro" entry point on the Library home for free users (P9.4): a small toolbar button, no
/// badge, no animation. Hidden for Pro and on the Player's embedded Library sheet. Tapping it is
/// user-initiated: `ScanQuota.requestPaywall(.library)` (uncapped by the shared policy).
enum LibraryProEntry {
    static let title = "Go Pro"
    static func isVisible(isPro: Bool, isHomeChrome: Bool) -> Bool { isHomeChrome && !isPro }
}
