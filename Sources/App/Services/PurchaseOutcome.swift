import Foundation

/// StoreKit-free purchase / restore result rules (user-facing text, status, terminal analytics event).
/// `StoreKitManager` maps StoreKit results to these outcomes and applies the resolution.

/// Coarse class of a StoreKit failure (no StoreKit types, so it is testable anywhere).
enum PurchaseFailureKind: String, Equatable, Sendable, CaseIterable {
    case cancelled, network, notAvailable, notAllowed, verification, unknown
}

/// What the paywall shows for the last purchase attempt. `pending` (Ask to Buy / SCA) is not an error.
enum PurchaseStatus: Equatable, Sendable {
    case idle
    case pending
    case error(String)
}

enum PurchaseOutcome: Equatable, Sendable {
    case success
    case cancelled
    case pending
    /// `.success(.unverified)`: left unfinished, never grants Pro.
    case unverified
    case failed(PurchaseFailureKind)
    /// `@unknown default` from StoreKit.
    case unknown
}

enum RestoreOutcome: Equatable, Sendable {
    case restored
    case nothingToRestore
    case cancelled
    case failed(PurchaseFailureKind)
}

struct PurchaseResolution: Equatable, Sendable {
    let status: PurchaseStatus
    /// The one terminal analytics event for this attempt (`nil` = none).
    let event: String?
    let props: [String: String]
    let succeeded: Bool
}

struct RestoreResolution: Equatable, Sendable {
    /// User-facing failure text (`nil` = nothing to show).
    let errorMessage: String?
    let event: String?
    let props: [String: String]
}

enum PurchaseResolver {
    static let pendingMessage = "Waiting for approval. Pro unlocks automatically once the purchase is approved."

    static func userMessage(for kind: PurchaseFailureKind) -> String {
        "The operation couldn't be completed."
    }

    static func resolve(_ outcome: PurchaseOutcome, productID: String) -> PurchaseResolution {
        switch outcome {
        case .success:
            return PurchaseResolution(status: .idle, event: "purchase_success", props: ["product": productID], succeeded: true)
        case .cancelled:
            return PurchaseResolution(status: .idle, event: nil, props: [:], succeeded: false)
        case .pending:
            return PurchaseResolution(
                status: .error("Purchase is pending approval."), event: "purchase_fail",
                props: ["reason": "pending"], succeeded: false)
        case .unverified, .failed:
            return PurchaseResolution(
                status: .error(userMessage(for: .unknown)), event: "purchase_fail",
                props: ["reason": "error"], succeeded: false)
        case .unknown:
            return PurchaseResolution(status: .idle, event: nil, props: [:], succeeded: false)
        }
    }

    static func resolve(_ outcome: RestoreOutcome) -> RestoreResolution {
        RestoreResolution(errorMessage: nil, event: nil, props: [:])
    }

    /// Status after an entitlement refresh: a pending purchase that got approved clears itself.
    static func status(afterEntitlementRefresh status: PurchaseStatus, isPro: Bool) -> PurchaseStatus {
        status
    }
}
