import Foundation

/// Combines Open Food Facts (barcodes) and USDA (generic-food text search)
/// behind a single ``FoodDataSource``, so feature code never has to pick
/// between them.
///
/// A plain `struct`, not an actor: it holds no mutable state of its own,
/// just two existentials it delegates to, and both of those already handle
/// their own concurrency.
struct CompositeFoodDataSource: FoodDataSource {
    private let openFoodFacts: any FoodDataSource
    private let usda: any FoodDataSource

    init(openFoodFacts: any FoodDataSource, usda: any FoodDataSource) {
        self.openFoodFacts = openFoodFacts
        self.usda = usda
    }

    /// Open Food Facts is the authoritative barcode source and is tried
    /// first. Only its `productNotFound` — the ordinary "OFF doesn't have
    /// this one" outcome — falls through to USDA's thinner barcode support;
    /// any other error (offline, rate limited) is surfaced as-is rather than
    /// masked by a second lookup.
    func product(barcode: String) async throws -> FoodRecord {
        do {
            return try await openFoodFacts.product(barcode: barcode)
        } catch FoodDataError.productNotFound {
            return try await usda.product(barcode: barcode)
        }
    }

    /// USDA is the primary search source for generic foods. When no USDA key
    /// is configured, search degrades to Open Food Facts rather than
    /// surfacing ``FoodDataError/missingAPIKey`` on a screen the user never
    /// asked to configure anything on — the app works, just with a weaker
    /// search, until a key is added.
    func search(query: String, page: Int) async throws -> [FoodRecord] {
        do {
            return try await usda.search(query: query, page: page)
        } catch FoodDataError.missingAPIKey {
            return try await openFoodFacts.search(query: query, page: page)
        }
    }
}
