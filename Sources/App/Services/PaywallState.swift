import Foundation

/// Paywall product-load state and Restore feedback rules (StoreKit-free, testable anywhere).

enum PaywallLoadState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed(String)
}

/// What the paywall's product area renders.
struct PaywallProductsDisplay: Equatable, Sendable {
    var showsSpinner: Bool
    var showsProducts: Bool
    /// At most one user-facing message.
    var messages: [String]
    var showsRetry: Bool
}

enum PaywallState {
    static let emptyMessage = "No subscription options are available right now. Please try again."

    static func loadFailureMessage(for kind: PurchaseFailureKind) -> String {
        "Could not load products. Check your connection and try again."
    }

    static func display(_ state: PaywallLoadState, hasProducts: Bool) -> PaywallProductsDisplay {
        var messages: [String] = []
        if !hasProducts, state != .loading {
            messages.append("Could not load products. Check your connection and try again.")
        }
        if case .failed(let message) = state { messages.append(message) }
        return PaywallProductsDisplay(showsSpinner: false, showsProducts: hasProducts, messages: messages, showsRetry: false)
    }
}

/// How the paywall reacts to the outcome of tapping Restore purchases.
struct RestoreFeedback: Equatable, Sendable {
    let text: String?
    let isError: Bool
    let dismissPaywall: Bool

    static func resolve(_ outcome: RestoreOutcome) -> RestoreFeedback {
        RestoreFeedback(text: nil, isError: false, dismissPaywall: false)
    }
}
