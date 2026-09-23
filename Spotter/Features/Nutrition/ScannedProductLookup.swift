import Foundation

/// Outcome of looking a scanned barcode up through ``CachingFoodRepository``.
///
/// Kept out of the view so the routing — found, no nutrition panel, unknown
/// product, transport failure — can be unit tested without a scanner or a
/// sheet. ``AddFoodView`` is the only caller; this is not a general food API.
@MainActor
enum ScannedProductResult {
    /// Cached or freshly fetched, with a usable energy figure. Log it.
    case product(FoodItem)
    /// The source knew the product but published no nutrition panel. Route to
    /// manual entry, editing the already-cached row so a later save updates
    /// it rather than inserting a duplicate barcode.
    case missingNutrition(FoodItem)
    /// Open Food Facts (and USDA fallback) have never heard of this barcode.
    /// Offer a blank custom food with the barcode prefilled.
    case notFound(barcode: String)
    /// Offline, rate limited, and so on. The view decides whether to retry
    /// or fall through to manual entry via ``FoodDataError/suggestedAction``.
    case failed(FoodDataError)
}

/// Resolves a raw barcode string into a ``ScannedProductResult``.
@MainActor
enum ScannedProductLookup {

    static func resolve(
        barcode: String,
        using repository: CachingFoodRepository
    ) async -> ScannedProductResult {
        let trimmed = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .notFound(barcode: barcode) }

        do {
            let item = try await repository.product(barcode: trimmed)
            if item.nutrientsPer100g.effectiveKcal == nil {
                return .missingNutrition(item)
            }
            return .product(item)
        } catch let error as FoodDataError {
            if error == .productNotFound {
                return .notFound(barcode: trimmed)
            }
            return .failed(error)
        } catch {
            return .failed(.offline)
        }
    }
}
