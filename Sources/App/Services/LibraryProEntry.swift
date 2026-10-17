import Foundation

/// Quiet "Go Pro" entry point on the Library home for free users (P9.4). TODO: stub (legacy: no entry).
enum LibraryProEntry {
    static let title = "Go Pro"
    static func isVisible(isPro: Bool, isHomeChrome: Bool) -> Bool { false }
}
