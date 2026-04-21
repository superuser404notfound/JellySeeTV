import Foundation
import Observation
import StoreKit

/// Result of a single purchase attempt, flattened from StoreKit 2's
/// `Product.PurchaseResult` so the UI layer doesn't have to know about
/// `VerificationResult` or `@unknown default`.
enum PurchaseOutcome: Sendable {
    /// Transaction verified and finished.
    case success
    /// User backed out of the purchase sheet.
    case userCancelled
    /// Waiting on a parental approval or SCA challenge — no entitlement yet,
    /// but a later `Transaction.updates` callback may still grant one.
    case pending
}

enum StoreKitServiceError: Error {
    /// StoreKit returned an unverified JWS — someone forged a transaction
    /// or the App Store key is stale. Never trust the entitlement.
    case verificationFailed
}

@MainActor
protocol StoreKitServiceProtocol: AnyObject {
    var isSupporter: Bool { get }
    var tipProducts: [Product] { get }
    var supporterPackProduct: Product? { get }
    var hasLoadedProducts: Bool { get }

    func loadProducts() async
    func purchase(_ product: Product) async throws -> PurchaseOutcome
    func restorePurchases() async throws
    func refreshSupporterStatus() async
}

/// Owns the StoreKit 2 session for JellySeeTV: loads products, runs
/// purchases, verifies transactions, and exposes a single observable
/// `isSupporter` flag that the UI reacts to.
///
/// The service caches `isSupporter` in `UserDefaults` so the first frame
/// after launch already reflects the last known entitlement state — the
/// authoritative refresh against `Transaction.currentEntitlements`
/// happens asynchronously on app start and overwrites the cache.
@MainActor
@Observable
final class StoreKitService: StoreKitServiceProtocol {

    // MARK: - Observable State

    private(set) var isSupporter: Bool
    private(set) var tipProducts: [Product] = []
    private(set) var supporterPackProduct: Product?
    private(set) var hasLoadedProducts: Bool = false

    // MARK: - Private

    private let store: UserDefaults

    private enum Keys {
        static let cachedIsSupporter = "store.cachedIsSupporter"
    }

    // MARK: - Init

    init(store: UserDefaults = .standard) {
        self.store = store
        self.isSupporter = store.bool(forKey: Keys.cachedIsSupporter)
        // The listener task runs for the lifetime of the app — the
        // service is held by DependencyContainer, which itself lives
        // as long as the process. No cancel/deinit bookkeeping needed;
        // the task captures `self` weakly so it can't keep us alive.
        Self.startTransactionListener { [weak self] transaction in
            await self?.handle(transaction: transaction)
        }
    }

    // MARK: - Product Loading

    func loadProducts() async {
        do {
            let products = try await Product.products(for: StoreProducts.allProductIDs)

            var tips: [Product] = []
            var pack: Product?
            for product in products {
                if StoreProducts.isTipJar(product.id) {
                    tips.append(product)
                } else if StoreProducts.isSupporterPack(product.id) {
                    pack = product
                }
            }
            tips.sort { $0.price < $1.price }

            self.tipProducts = tips
            self.supporterPackProduct = pack
            self.hasLoadedProducts = true
        } catch {
            #if DEBUG
            print("[StoreKit] loadProducts failed: \(error)")
            #endif
        }
    }

    // MARK: - Purchasing

    func purchase(_ product: Product) async throws -> PurchaseOutcome {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try Self.verify(verification)
            await handle(transaction: transaction)
            await transaction.finish()
            return .success
        case .userCancelled:
            return .userCancelled
        case .pending:
            return .pending
        @unknown default:
            return .pending
        }
    }

    func restorePurchases() async throws {
        // Forces a refresh against the App Store. Not needed for the
        // happy path (Transaction.currentEntitlements already knows
        // about non-consumables restored by Apple ID) but required by
        // App Review — and covers the edge case where a device was
        // offline the last time entitlements changed.
        try await AppStore.sync()
        await refreshSupporterStatus()
    }

    // MARK: - Entitlement Refresh

    func refreshSupporterStatus() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if StoreProducts.isSupporterPack(transaction.productID),
               transaction.revocationDate == nil {
                active = true
            }
        }
        setSupporter(active)
    }

    // MARK: - Internal Helpers

    private func handle(transaction: Transaction) async {
        if StoreProducts.isSupporterPack(transaction.productID) {
            setSupporter(transaction.revocationDate == nil)
        }
        // Tip purchases are consumables — nothing to unlock, they exist
        // purely for their own sake. Just finish them in the caller.
    }

    private func setSupporter(_ value: Bool) {
        isSupporter = value
        store.set(value, forKey: Keys.cachedIsSupporter)
    }

    private static func verify<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe): return safe
        case .unverified: throw StoreKitServiceError.verificationFailed
        }
    }

    /// Background listener for transactions that arrive outside the main
    /// purchase flow — parental approvals landing after `.pending`, Ask-
    /// To-Buy completions, or purchases made on another device for the
    /// same Apple ID. Apple requires every app with IAP to attach a
    /// listener early in the lifecycle so nothing is missed.
    private static func startTransactionListener(
        handler: @escaping @Sendable (Transaction) async -> Void
    ) {
        Task {
            for await update in Transaction.updates {
                guard case .verified(let transaction) = update else { continue }
                await handler(transaction)
                await transaction.finish()
            }
        }
    }
}
