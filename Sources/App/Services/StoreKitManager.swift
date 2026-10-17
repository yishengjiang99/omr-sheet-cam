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
    @Published private(set) var isLoading = false
    @Published var purchaseError: String?
    @Published private(set) var isPurchasing = false

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
        isLoading = true
        purchaseError = nil
        defer { isLoading = false }
        do {
            let loaded = try await Product.products(for: IAPProductID.all)
            products = loaded.sorted { lhs, rhs in
                if lhs.id == IAPProductID.yearly { return true }
                if rhs.id == IAPProductID.yearly { return false }
                return lhs.price < rhs.price
            }
        } catch {
            purchaseError = "Could not load products: \(error.localizedDescription)"
        }
    }

    func purchase(_ product: Product) async -> Bool {
        isPurchasing = true
        purchaseError = nil
        defer { isPurchasing = false }
        Analytics.shared.track("purchase_start", props: ["product": product.id])
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await refresh(extra: [EntitlementSnapshot(transaction)])
                Analytics.shared.track("purchase_success", props: ["product": product.id])
                return true
            case .userCancelled:
                return false
            case .pending:
                purchaseError = "Purchase is pending approval."
                Analytics.shared.track("purchase_fail", props: ["reason": "pending"])
                return false
            @unknown default:
                return false
            }
        } catch {
            purchaseError = error.localizedDescription
            Analytics.shared.track("purchase_fail", props: ["reason": "error"])
            return false
        }
    }

    func restore() async {
        isLoading = true
        purchaseError = nil
        defer { isLoading = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            purchaseError = "Restore failed: \(error.localizedDescription)"
        }
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
        .unknown
    }
}
