import Foundation
import Testing

@testable import Spotter

/// A fake ``FoodDataSource`` that always fails the same way, for exercising
/// ``CompositeFoodDataSource``'s fallback logic without any real client.
private struct FailingFoodDataSource: FoodDataSource {
    let error: FoodDataError

    func product(barcode: String) async throws -> FoodRecord {
        throw error
    }

    func search(query: String, page: Int) async throws -> [FoodRecord] {
        throw error
    }
}

@Suite("CompositeFoodDataSource")
struct CompositeFoodDataSourceTests {

    @Test("Barcode lookup falls back to USDA only when OFF reports the product unknown")
    func barcodeFallsBackOnNotFound() async throws {
        let off = FailingFoodDataSource(error: .productNotFound)
        let usda = MockFoodDataSource(records: [
            FoodRecord(
                sourceID: "1", source: .usda, name: "Found On USDA",
                barcode: "123", nutrientsPer100g: Nutrients(kcal: 50)
            ),
        ])
        let composite = CompositeFoodDataSource(openFoodFacts: off, usda: usda)

        let record = try await composite.product(barcode: "123")
        #expect(record.name == "Found On USDA")
    }

    @Test("Barcode lookup does not fall back to USDA on a non-not-found OFF error")
    func barcodeDoesNotFallBackOnOtherErrors() async throws {
        let off = FailingFoodDataSource(error: .rateLimited)
        let usda = MockFoodDataSource() // would happily answer if reached
        let composite = CompositeFoodDataSource(openFoodFacts: off, usda: usda)

        let error = try await #require(throws: FoodDataError.self) {
            try await composite.product(barcode: "9300675024235")
        }
        #expect(error == .rateLimited)
    }

    @Test("Search degrades to Open Food Facts when USDA has no API key configured")
    func searchFallsBackToOFFWithNoUSDAKey() async throws {
        let usda = FailingFoodDataSource(error: .missingAPIKey)
        let off = MockFoodDataSource(records: [
            FoodRecord(
                sourceID: "1", source: .openFoodFacts, name: "Off Result",
                nutrientsPer100g: Nutrients(kcal: 10)
            ),
        ])
        let composite = CompositeFoodDataSource(openFoodFacts: off, usda: usda)

        let results = try await composite.search(query: "Off Result")
        #expect(results.map(\.name) == ["Off Result"])
    }

    @Test("Search does not fall back to Open Food Facts on a non-key USDA error")
    func searchDoesNotFallBackOnOtherErrors() async throws {
        let usda = FailingFoodDataSource(error: .offline)
        let off = MockFoodDataSource()
        let composite = CompositeFoodDataSource(openFoodFacts: off, usda: usda)

        let error = try await #require(throws: FoodDataError.self) {
            try await composite.search(query: "anything")
        }
        #expect(error == .offline)
    }
}
