import Foundation

/// Central registry of in-app purchase product identifiers.
///
/// These IDs must match the products configured in App Store Connect
/// for the JellySeeTV app (`de.superuser404.JellySeeTV`).
///
/// Tip jar items are **consumables** — the user can buy them repeatedly,
/// each purchase is independent. The Supporter Pack is **non-consumable**
/// — a one-time unlock restored across devices through the App Store.
enum StoreProducts {

    // MARK: - Tip Jar (consumables)

    static let tipCoffee = "de.superuser404.JellySeeTV.tip.coffee"
    static let tipBeer   = "de.superuser404.JellySeeTV.tip.beer"
    static let tipPizza  = "de.superuser404.JellySeeTV.tip.pizza"

    // MARK: - Supporter Pack (non-consumable)

    static let supporterPack = "de.superuser404.JellySeeTV.supporter.pack"

    // MARK: - Groups

    static let allTipIDs: [String] = [tipCoffee, tipBeer, tipPizza]
    static let allNonConsumableIDs: [String] = [supporterPack]
    static let allProductIDs: [String] = allTipIDs + allNonConsumableIDs

    static func isTipJar(_ id: String) -> Bool {
        allTipIDs.contains(id)
    }

    static func isSupporterPack(_ id: String) -> Bool {
        id == supporterPack
    }
}
