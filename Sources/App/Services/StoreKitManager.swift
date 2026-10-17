import Foundation
import StoreKit

/// Product IDs — must match App Store Connect exactly.
enum IAPProductID {
    static let monthly = "com.ragnus.vp.pro.monthly"
    static let yearly = "com.ragnus.vp.pro.yearly"
    static let all: Set<String> = [monthly, yearly]
}

@MainActor
final class StoreKitManager: ObservableObject, ProEntitlementSource {
    /// App-wide instance (one `Transaction.updates` listener, one entitlement refresh).
    static let shared = StoreKitManager()

    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIDs: Set<String> = []
    /// Product-load state (spinner / products / one message + Retry on the paywall).
    @Published private(set) var loadState: PaywallLoadState = .idle
    /// Last purchase attempt: idle, pending (Ask to Buy / SCA, not an error) or a user-facing error.
    @Published private(set) var purchaseStatus: PurchaseStatus = .idle
    @Published private(set) var isPurchasing = false
    /// A purchase is running or waiting for Ask to Buy approval: upsell surfaces stay quiet (P2.1).
    var purchaseInFlight: Bool {
        if isPurchasing { return true }
        if case .pending = purchaseStatus { return true }
        return false
    }

    /// Pro state. Cached in UserDefaults as an offline fallback only; re-derived from
    /// `Transaction.currentEntitlements` on launch, foreground, every `Transaction.updates` event
    /// and before each scan (`ScanQuota.admitScan`).
    @Published private(set) var isPro = UserDefaults.standard.bool(forKey: StoreKitManager.proKey)

    private var updatesTask: Task<Void, Never>?
    private var refreshSeq = 0
    private var appliedSeq = 0
    private static let proKey = "omr.isPro"
    private static let proTxKey = "omr.proTransactionId"

    init() {
        // Hold self weakly between updates (unwrapping it once for the whole loop kept it alive forever).
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                await self.handle(update)
            }
        }
        Task { await refreshEntitlements() }
    }

    deinit {
        updatesTask?.cancel()
    }

    var yearlyProduct: Product? {
        products.first { $0.id == IAPProductID.yearly }
    }

    var monthlyProduct: Product? {
        products.first { $0.id == IAPProductID.monthly }
    }

    func loadProducts() async {
        if loadState == .loading { return }
        loadState = .loading
        do {
            let loaded = try await Product.products(for: IAPProductID.all)
            products = loaded.sorted { lhs, rhs in
                if lhs.id == IAPProductID.yearly { return true }
                if rhs.id == IAPProductID.yearly { return false }
                return lhs.price < rhs.price
            }
            loadState = .loaded
        } catch {
            DiagnosticsLog.shared.record(error: error, category: .app, context: "load products failed")
            loadState = .failed(PaywallState.loadFailureMessage(for: PurchaseFailureKind.classify(error)))
        }
    }

    func purchase(_ product: Product) async -> Bool {
        isPurchasing = true
        purchaseStatus = .idle
        defer { isPurchasing = false }
        Analytics.shared.track("purchase_start", props: ["product": product.id])
        let outcome: PurchaseOutcome
        do {
            switch try await product.purchase() {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    await refresh(extra: [EntitlementSnapshot(transaction)])
                    outcome = .success
                case .unverified(_, let error):
                    // Left unfinished and never grants Pro; the user is pointed to Restore.
                    DiagnosticsLog.shared.record(error: error, category: .app, context: "purchase unverified")
                    outcome = .unverified
                }
            case .userCancelled:
                outcome = .cancelled
            case .pending:
                outcome = .pending
            @unknown default:
                outcome = .unknown
            }
        } catch {
            DiagnosticsLog.shared.record(error: error, category: .app, context: "purchase failed")
            outcome = .failed(PurchaseFailureKind.classify(error))
        }
        let resolution = PurchaseResolver.resolve(outcome, productID: product.id)
        purchaseStatus = resolution.status
        if let event = resolution.event { Analytics.shared.track(event, props: resolution.props) }
        return resolution.succeeded
    }

    /// Restore purchases (App Store sync + entitlement refresh). The UI shows the returned outcome.
    @discardableResult
    func restore() async -> RestoreOutcome {
        Analytics.shared.track("restore_start")
        let outcome: RestoreOutcome
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            outcome = isPro ? .restored : .nothingToRestore
        } catch {
            DiagnosticsLog.shared.record(error: error, category: .app, context: "restore failed")
            outcome = .failed(PurchaseFailureKind.classify(error))
        }
        let resolution = PurchaseResolver.resolve(outcome)
        if let event = resolution.event { Analytics.shared.track(event, props: resolution.props) }
        return outcome
    }

    private func handle(_ update: VerificationResult<Transaction>) async {
        guard let transaction = try? checkVerified(update),
              IAPProductID.all.contains(transaction.productID) else { return }
        await transaction.finish()
        // Never patch Pro per transaction: recompute from the full current entitlement list.
        await refresh(update: EntitlementSnapshot(transaction))
    }

    func refreshEntitlements() async {
        await refresh()
    }

    /// Recompute Pro from `Transaction.currentEntitlements` (+ `extra`, e.g. the just-bought transaction).
    private func refresh(update: EntitlementSnapshot? = nil, extra: [EntitlementSnapshot] = []) async {
        refreshSeq += 1
        let seq = refreshSeq
        var snapshots = extra
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result { snapshots.append(EntitlementSnapshot(transaction)) }
        }
        // An older refresh that finishes after a newer one must not overwrite it.
        guard seq > appliedSeq else { return }
        appliedSeq = seq
        let active = EntitlementLogic.activeEntitlements(snapshots, validIDs: IAPProductID.all)
        purchasedProductIDs = Set(active.map(\.productID))
        let pro: Bool
        if let update {
            pro = EntitlementLogic.proAfterUpdate(
                current: isPro, update: update, entitlements: snapshots, validIDs: IAPProductID.all)
        } else {
            pro = EntitlementLogic.isPro(entitlements: snapshots, validIDs: IAPProductID.all)
        }
        isPro = pro
        purchaseStatus = PurchaseResolver.status(afterEntitlementRefresh: purchaseStatus, isPro: pro)
        let defaults = UserDefaults.standard
        defaults.set(pro, forKey: Self.proKey)
        if pro, let latest = active.map(\.transactionID).max() {
            defaults.set(String(latest), forKey: Self.proTxKey)
        } else {
            defaults.removeObject(forKey: Self.proTxKey)
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }
}

extension EntitlementSnapshot {
    init(_ t: Transaction) {
        self.init(
            productID: t.productID, transactionID: t.id, revocationDate: t.revocationDate,
            isUpgraded: t.isUpgraded)
    }
}

extension PurchaseFailureKind {
    /// Map a thrown StoreKit / URL error to a coarse kind.
    static func classify(_ error: Error) -> PurchaseFailureKind {
        if let e = error as? StoreKitError {
            switch e {
            case .userCancelled: return .cancelled
            case .networkError: return .network
            case .notAvailableInStorefront: return .notAvailable
            default: return .unknown
            }
        }
        if let e = error as? Product.PurchaseError {
            switch e {
            case .purchaseNotAllowed: return .notAllowed
            case .productUnavailable: return .notAvailable
            default: return .unknown
            }
        }
        if error is VerificationResult<Transaction>.VerificationError { return .verification }
        if error is URLError { return .network }
        return .unknown
    }
}
