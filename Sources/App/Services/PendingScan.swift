import Foundation

/// The scan that hit the paywall. Held while the paywall is up and re-submitted if the user ends up
/// Pro (purchase, restore, or an approved Ask to Buy); dropped if they close it still free.
struct PendingScan<Item> {
    private(set) var item: Item?

    /// Gate rejected `item`: keep it for the paywall.
    mutating func hold(_ item: Item) {
        self.item = item
    }

    /// Paywall closed. Returns the item to re-submit (only if Pro is now active); clears either way.
    mutating func take(isPro: Bool) -> Item? {
        defer { item = nil }
        return isPro ? item : nil
    }
}
