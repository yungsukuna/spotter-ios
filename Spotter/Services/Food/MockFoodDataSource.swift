import Foundation

/// An in-memory ``FoodDataSource`` for previews, tests, and building UI before
/// the real clients exist.
///
/// Configurable so a caller can force the awkward paths — not found, offline,
/// rate limited, a product with no nutrition panel — without touching the
/// network. Those paths are the ones worth designing against: in practice a
/// barcode scanner spends a surprising amount of its life looking at products
/// Open Food Facts has never heard of.
final class MockFoodDataSource: FoodDataSource, @unchecked Sendable {

    /// Forced outcome for the next call, if any.
    var stubbedError: FoodDataError?
    /// Artificial latency, so loading states are actually visible in previews.
    var responseDelay: Duration = .zero
    /// The catalogue searched and scanned against.
    var records: [FoodRecord]

    init(records: [FoodRecord] = MockFoodDataSource.sampleRecords) {
        self.records = records
    }

    func product(barcode: String) async throws -> FoodRecord {
        try await applyStub()
        guard let match = records.first(where: { $0.barcode == barcode }) else {
            throw FoodDataError.productNotFound
        }
        return match
    }

    func search(query: String, page: Int) async throws -> [FoodRecord] {
        try await applyStub()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard page == 1 else { return [] }
        return records.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
                || ($0.brand?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }

    private func applyStub() async throws {
        if responseDelay > .zero {
            try? await Task.sleep(for: responseDelay)
        }
        if let stubbedError {
            throw stubbedError
        }
    }
}

extension MockFoodDataSource {

    /// A small catalogue covering the shapes real data actually takes: a
    /// complete branded product, a generic whole food, one with an awkward
    /// serving size, and one with no nutrition panel at all.
    static let sampleRecords: [FoodRecord] = [
        FoodRecord(
            sourceID: "9300675024235",
            source: .openFoodFacts,
            name: "Weet-Bix",
            brand: "Sanitarium",
            barcode: "9300675024235",
            nutrientsPer100g: Nutrients(
                kcal: 349,
                proteinG: 12.9,
                carbsG: 67.1,
                fatG: 1.3,
                satFatG: 0.3,
                sugarG: 3.3,
                fiberG: 11.5,
                sodiumMG: 270
            ),
            servings: [
                ServingSize(label: "2 biscuits", gramWeight: 30),
                ServingSize(label: "100 g", gramWeight: 100),
            ]
        ),
        FoodRecord(
            sourceID: "171077",
            source: .usda,
            name: "Chicken breast, raw, boneless, skinless",
            brand: nil,
            barcode: nil,
            nutrientsPer100g: Nutrients(
                kcal: 120,
                proteinG: 22.5,
                carbsG: 0,
                fatG: 2.6,
                satFatG: 0.6,
                sugarG: 0,
                fiberG: 0,
                sodiumMG: 45
            ),
            servings: [
                ServingSize(label: "100 g", gramWeight: 100),
                ServingSize(label: "1 breast", gramWeight: 174),
            ]
        ),
        FoodRecord(
            sourceID: "737628064502",
            source: .openFoodFacts,
            name: "Thai Peanut Noodle Kit",
            brand: "Simply Asia",
            barcode: "737628064502",
            nutrientsPer100g: Nutrients(
                kcal: 385,
                proteinG: 9.62,
                carbsG: 71.15,
                fatG: 7.69,
                satFatG: 1.92,
                sugarG: 13.46,
                fiberG: 1.9,
                sodiumMG: 288
            ),
            // A real awkward case: the source's own serving is a third of the
            // package, which is not a round number of grams.
            servings: [
                ServingSize(label: "0.333 package", gramWeight: 52),
                ServingSize(label: "100 g", gramWeight: 100),
            ]
        ),
        FoodRecord(
            sourceID: "5000112637922",
            source: .openFoodFacts,
            name: "Sparkling Water, Lime",
            brand: "Generic",
            barcode: "5000112637922",
            // Genuinely zero, as opposed to unknown — a useful contrast with
            // the record below.
            nutrientsPer100g: Nutrients(kcal: 0, proteinG: 0, carbsG: 0, fatG: 0),
            servings: [ServingSize(label: "1 can", gramWeight: 330)]
        ),
        FoodRecord(
            sourceID: "0000000000000",
            source: .openFoodFacts,
            name: "Unlabelled Bakery Item",
            brand: nil,
            barcode: "0000000000000",
            // No panel at all. `lacksNutrition` is true; the UI should route
            // this to manual entry rather than offer it for logging.
            nutrientsPer100g: .empty,
            servings: []
        ),
    ]

    /// A source that always reports the product as unknown — the most common
    /// real-world scanner outcome, and the one the UI must handle gracefully.
    static func alwaysNotFound() -> MockFoodDataSource {
        let source = MockFoodDataSource(records: [])
        source.stubbedError = .productNotFound
        return source
    }

    /// A source that always fails as if there were no network.
    static func alwaysOffline() -> MockFoodDataSource {
        let source = MockFoodDataSource(records: [])
        source.stubbedError = .offline
        return source
    }
}
