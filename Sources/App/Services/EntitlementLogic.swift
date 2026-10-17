import Foundation

/// StoreKit-free entitlement rules (testable without a StoreKit session).
/// `StoreKitManager` maps `Transaction`s to `EntitlementSnapshot`s and applies these rules.

/// What the Pro gate needs: current Pro state plus a way to re-check it right now.
@MainActor
protocol ProEntitlementSource: AnyObject {
    var isPro: Bool { get }
    /// Re-evaluate Pro from the store (`Transaction.currentEntitlements`) and update `isPro`.
    func refreshEntitlements() async
}

/// One transaction as the entitlement rules see it.
struct EntitlementSnapshot: Equatable, Sendable {
    let productID: String
    let transactionID: UInt64
    let revocationDate: Date?
    /// Superseded by an upgrade to another product in the group.
    let isUpgraded: Bool
}

enum EntitlementLogic {
    /// Entitlements that currently grant Pro. (Expiry is decided by StoreKit: `currentEntitlements`
    /// only lists active subscriptions, including billing grace period.)
    static func activeEntitlements(_ snapshots: [EntitlementSnapshot], validIDs: Set<String>) -> [EntitlementSnapshot] {
        snapshots.filter { validIDs.contains($0.productID) && $0.revocationDate == nil && !$0.isUpgraded }
    }

    /// Pro derived from the full list of current entitlements.
    static func isPro(entitlements: [EntitlementSnapshot], validIDs: Set<String>) -> Bool {
        !activeEntitlements(entitlements, validIDs: validIDs).isEmpty
    }

    /// Pro after `Transaction.updates` delivered `update`. The update only says "something changed":
    /// the answer is always recomputed from `entitlements` (the full current list), never patched per
    /// transaction (one refund must not lock out another valid entitlement; a replayed expired
    /// transaction must not grant Pro).
    static func proAfterUpdate(
        current: Bool, update: EntitlementSnapshot, entitlements: [EntitlementSnapshot], validIDs: Set<String>
    ) -> Bool {
        guard validIDs.contains(update.productID) else { return current }
        return isPro(entitlements: entitlements, validIDs: validIDs)
    }
}

extension ScanQuota {
    /// Scan gate: re-check Pro against the store first (expiry, refund or renewal while the app was
    /// alive), then consume one free scan if allowed. Returns true if the scan may proceed.
    func admitScan() async -> Bool {
        await storeKit.refreshEntitlements()
        return checkAndConsume()
    }
}
