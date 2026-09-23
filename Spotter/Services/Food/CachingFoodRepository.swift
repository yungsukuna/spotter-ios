import Foundation
import SwiftData

/// Wraps a ``FoodDataSource`` with a local SwiftData cache keyed on barcode.
///
/// `ModelContext` is not `Sendable`, so this type is pinned to `@MainActor`
/// rather than attempting to carry a context across actor boundaries —
/// SwiftUI's own view code already runs on the main actor, so every caller
/// can reach this without hopping actors.
@MainActor
final class CachingFoodRepository {
    private let remote: any FoodDataSource
    private let context: ModelContext

    init(remote: any FoodDataSource, context: ModelContext) {
        self.remote = remote
        self.context = context
    }

    /// Looks up a product by barcode, checking the local cache first.
    ///
    /// This is what makes a repeat scan instant and offline-capable, and it
    /// is also how Open Food Facts' 15/min rate limit stays comfortable in
    /// practice: a given barcode only ever needs to hit the network once.
    func product(barcode: String) async throws -> FoodItem {
        if let cached = try fetchCachedItem(barcode: barcode) {
            return cached
        }
        let record = try await remote.product(barcode: barcode)
        return try store(record)
    }

    /// Free-text search always hits the network. Search results are not
    /// cached as `FoodItem` rows — only a resolved barcode lookup is, because
    /// a search hit has no stable key to dedupe future searches against, and
    /// caching it would just mean showing stale results.
    func search(query: String, page: Int = 1) async throws -> [FoodRecord] {
        try await remote.search(query: query, page: page)
    }

    // MARK: - Cache

    /// Internal rather than `private` so tests can exercise the dedupe and
    /// custom-preservation logic directly, without needing to fabricate a
    /// network race to reach it through ``product(barcode:)``.
    func fetchCachedItem(barcode: String) throws -> FoodItem? {
        var descriptor = FetchDescriptor<FoodItem>(
            predicate: #Predicate<FoodItem> { $0.barcode == barcode }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Persists a freshly-fetched record.
    ///
    /// Updates the existing cached row in place when one already exists for
    /// this barcode — `FoodItem.barcode` carries a unique constraint, so a
    /// plain insert would either crash or silently violate it — and never
    /// touches a row the user has hand-edited (`isCustom == true`), since a
    /// remote refresh must not clobber someone's own correction.
    @discardableResult
    func store(_ record: FoodRecord) throws -> FoodItem {
        if let barcode = record.barcode, let existing = try fetchCachedItem(barcode: barcode) {
            guard !existing.isCustom else { return existing }
            existing.name = record.name
            existing.brand = record.brand
            existing.source = record.source
            existing.nutrientsPer100g = record.nutrientsPer100g
            existing.servings = record.servings
            try context.save()
            return existing
        }
        let item = record.makeFoodItem()
        context.insert(item)
        try context.save()
        return item
    }
}
