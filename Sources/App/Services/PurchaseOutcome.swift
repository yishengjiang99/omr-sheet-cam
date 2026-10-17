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

    /// Plain-language text per failure class. Raw `localizedDescription` / Swift error text never reaches
    /// the user (it goes to the diagnostics log instead).
    static func userMessage(for kind: PurchaseFailureKind) -> String {
        switch kind {
        case .cancelled: return "Purchase cancelled."
        case .network: return "Couldn't reach the App Store. Check your connection and try again."
        case .notAvailable: return "This subscription isn't available in your country or region right now."
        case .notAllowed: return "Purchases are turned off on this device. Check Screen Time or device restrictions."
        case .verification: return "We couldn't verify this purchase. If you were charged, tap Restore purchases."
        case .unknown: return "Something went wrong. Please try again, or tap Restore purchases if you were charged."
        }
    }

    /// One resolution per attempt: UI status, the single terminal analytics event, and the return value.
    static func resolve(_ outcome: PurchaseOutcome, productID: String) -> PurchaseResolution {
        func make(_ status: PurchaseStatus, _ event: String, _ extra: [String: String] = [:], ok: Bool = false) -> PurchaseResolution {
            PurchaseResolution(status: status, event: event, props: ["product": productID].merging(extra) { $1 }, succeeded: ok)
        }
        switch outcome {
        case .success:
            return make(.idle, "purchase_success", ok: true)
        case .cancelled, .failed(.cancelled):
            return make(.idle, "purchase_cancel")
        case .pending:
            return make(.pending, "purchase_pending")
        case .unverified:
            return make(.error(userMessage(for: .verification)), "purchase_fail", ["reason": PurchaseFailureKind.verification.rawValue])
        case .failed(let kind):
            return make(.error(userMessage(for: kind)), "purchase_fail", ["reason": kind.rawValue])
        case .unknown:
            return make(.error(userMessage(for: .unknown)), "purchase_fail", ["reason": PurchaseFailureKind.unknown.rawValue])
        }
    }

    static func resolve(_ outcome: RestoreOutcome) -> RestoreResolution {
        switch outcome {
        case .restored:
            return RestoreResolution(errorMessage: nil, event: "restore_success", props: [:])
        case .nothingToRestore:
            return RestoreResolution(errorMessage: nil, event: "restore_none", props: [:])
        case .cancelled, .failed(.cancelled):
            return RestoreResolution(errorMessage: nil, event: "restore_cancel", props: [:])
        case .failed(let kind):
            return RestoreResolution(errorMessage: userMessage(for: kind), event: "restore_fail", props: ["reason": kind.rawValue])
        }
    }

    /// Status after an entitlement refresh: once Pro is active, a pending (Ask to Buy approved) or old
    /// error state clears itself.
    static func status(afterEntitlementRefresh status: PurchaseStatus, isPro: Bool) -> PurchaseStatus {
        isPro ? .idle : status
    }
}
