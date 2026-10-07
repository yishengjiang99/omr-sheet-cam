import Foundation
import StoreKit

/// Product IDs — must match App Store Connect exactly.
enum IAPProductID {
    static let monthly = "com.ragnus.vp.pro.monthly"
    static let yearly = "com.ragnus.vp.pro.yearly"
    static let all: Set<String> = [monthly, yearly]
}

@MainActor
final class StoreKitManager: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIDs: Set<String> = []
    @Published private(set) var isLoading = false
    @Published var purchaseError: String?
    @Published private(set) var isPurchasing = false

    private var updatesTask: Task<Void, Never>?
    private let proKey = "omr.isPro"
    private let proTxKey = "omr.proTransactionId"

    init() {
        updatesTask = Task { [weak self] in
            await self?.listenForTransactions()
        }
        Task { await refreshEntitlements() }
    }

    deinit {
        updatesTask?.cancel()
    }

    var isPro: Bool {
        UserDefaults.standard.bool(forKey: proKey)
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
                grantPro(transactionId: String(transaction.id))
                purchasedProductIDs.insert(product.id)
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

    private func listenForTransactions() async {
        for await update in Transaction.updates {
            do {
                let transaction = try checkVerified(update)
                guard IAPProductID.all.contains(transaction.productID) else { continue }
                if transaction.revocationDate == nil {
                    grantPro(transactionId: String(transaction.id))
                    purchasedProductIDs.insert(transaction.productID)
                } else {
                    revokePro()
                    purchasedProductIDs.remove(transaction.productID)
                }
                await transaction.finish()
            } catch {
                // Ignore unverified updates
            }
        }
    }

    func refreshEntitlements() async {
        var ids = Set<String>()
        var hasPro = false
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)
                guard IAPProductID.all.contains(transaction.productID) else { continue }
                if transaction.revocationDate == nil {
                    ids.insert(transaction.productID)
                    hasPro = true
                }
            } catch {
                continue
            }
        }
        purchasedProductIDs = ids
        UserDefaults.standard.set(hasPro, forKey: proKey)
    }

    private func grantPro(transactionId: String) {
        UserDefaults.standard.set(true, forKey: proKey)
        UserDefaults.standard.set(transactionId, forKey: proTxKey)
    }

    private func revokePro() {
        UserDefaults.standard.set(false, forKey: proKey)
        UserDefaults.standard.removeObject(forKey: proTxKey)
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
