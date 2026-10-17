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

    /// Plain-language load-failure text (raw StoreKit / system text never reaches the user).
    static func loadFailureMessage(for kind: PurchaseFailureKind) -> String {
        switch kind {
        case .network: return "Couldn't load subscription options. Check your connection and try again."
        case .notAvailable: return "Subscriptions aren't available in your country or region right now."
        default: return "Couldn't load subscription options. Please try again."
        }
    }

    /// One state drives the product area: spinner until loaded (never an error on the first frame),
    /// then products, or exactly one message plus Retry.
    static func display(_ state: PaywallLoadState, hasProducts: Bool) -> PaywallProductsDisplay {
        func make(spinner: Bool = false, messages: [String] = [], retry: Bool = false) -> PaywallProductsDisplay {
            PaywallProductsDisplay(showsSpinner: spinner, showsProducts: hasProducts, messages: messages, showsRetry: retry)
        }
        if hasProducts { return make() }
        switch state {
        case .idle, .loading: return make(spinner: true)
        case .loaded: return make(messages: [emptyMessage], retry: true)
        case .failed(let message): return make(messages: [message], retry: true)
        }
    }
}

/// How the paywall reacts to the outcome of tapping Restore purchases.
struct RestoreFeedback: Equatable, Sendable {
    let text: String?
    let isError: Bool
    let dismissPaywall: Bool

    static func resolve(_ outcome: RestoreOutcome) -> RestoreFeedback {
        switch outcome {
        case .restored:
            return RestoreFeedback(text: "Pro restored", isError: false, dismissPaywall: true)
        case .nothingToRestore:
            return RestoreFeedback(text: "No active subscription found for this Apple ID", isError: false, dismissPaywall: false)
        case .cancelled, .failed(.cancelled):
            return RestoreFeedback(text: nil, isError: false, dismissPaywall: false)
        case .failed(let kind):
            return RestoreFeedback(text: PurchaseResolver.userMessage(for: kind), isError: true, dismissPaywall: false)
        }
    }
}
