import Foundation
import SwiftData
import Testing

@testable import Tally

@MainActor
@Suite("ScannedProductLookup")
struct ScannedProductLookupTests {

    private func makeRepository(remote: any FoodDataSource) throws -> CachingFoodRepository {
        let container = try TallySchema.makeContainer(inMemory: true)
        return CachingFoodRepository(remote: remote, context: ModelContext(container))
    }

    @Test("A known barcode with nutrition resolves to the cached product")
    func knownProduct() async throws {
        let repository = try makeRepository(remote: MockFoodDataSource())
        let result = await ScannedProductLookup.resolve(barcode: "9300675024235", using: repository)
        guard case .product(let item) = result else {
            Issue.record("expected .product, got \(String(describing: result))")
            return
        }
        #expect(item.name == "Weet-Bix")
        #expect(item.barcode == "9300675024235")
    }

    @Test("A known barcode with no nutrition panel routes to manual entry")
    func missingNutrition() async throws {
        let repository = try makeRepository(remote: MockFoodDataSource())
        let result = await ScannedProductLookup.resolve(barcode: "0000000000000", using: repository)
        guard case .missingNutrition(let item) = result else {
            Issue.record("expected .missingNutrition, got \(String(describing: result))")
            return
        }
        #expect(item.name == "Unlabelled Bakery Item")
        #expect(item.nutrientsPer100g.effectiveKcal == nil)
    }

    @Test("An unknown barcode offers a blank custom food with the code prefilled")
    func unknownProduct() async throws {
        let repository = try makeRepository(remote: MockFoodDataSource(records: []))
        let result = await ScannedProductLookup.resolve(barcode: "1111111111111", using: repository)
        guard case .notFound(let barcode) = result else {
            Issue.record("expected .notFound, got \(String(describing: result))")
            return
        }
        #expect(barcode == "1111111111111")
    }

    @Test("A genuinely zero-calorie drink is a product, not missing nutrition")
    func zeroCalorieIsProduct() async throws {
        let repository = try makeRepository(remote: MockFoodDataSource())
        let result = await ScannedProductLookup.resolve(barcode: "5000112637922", using: repository)
        guard case .product(let item) = result else {
            Issue.record("expected .product for a genuine zero, got \(String(describing: result))")
            return
        }
        #expect(item.nutrientsPer100g.kcal == 0)
        #expect(item.nutrientsPer100g.effectiveKcal == 0)
    }

    @Test("An offline failure surfaces as failed rather than not-found")
    func offlineFailure() async throws {
        let repository = try makeRepository(remote: MockFoodDataSource.alwaysOffline())
        let result = await ScannedProductLookup.resolve(barcode: "9300675024235", using: repository)
        guard case .failed(let error) = result else {
            Issue.record("expected .failed, got \(String(describing: result))")
            return
        }
        #expect(error == .offline)
    }

    @Test("Whitespace around a barcode is trimmed before lookup")
    func trimsBarcode() async throws {
        let repository = try makeRepository(remote: MockFoodDataSource())
        let result = await ScannedProductLookup.resolve(barcode: "  9300675024235  ", using: repository)
        guard case .product(let item) = result else {
            Issue.record("expected .product, got \(String(describing: result))")
            return
        }
        #expect(item.barcode == "9300675024235")
    }

    @Test("An empty barcode is treated as not found without touching the repository")
    func emptyBarcode() async throws {
        let remote = CountingCallsDataSource()
        let repository = try makeRepository(remote: remote)
        let result = await ScannedProductLookup.resolve(barcode: "   ", using: repository)
        guard case .notFound = result else {
            Issue.record("expected .notFound, got \(String(describing: result))")
            return
        }
        #expect(remote.productCallCount == 0)
    }
}

/// Minimal ``FoodDataSource`` that only counts `product` calls, so the empty-
/// barcode path can prove it never reaches the network.
private final class CountingCallsDataSource: FoodDataSource, @unchecked Sendable {
    private(set) var productCallCount = 0

    func product(barcode: String) async throws -> FoodRecord {
        productCallCount += 1
        throw FoodDataError.productNotFound
    }

    func search(query: String, page: Int) async throws -> [FoodRecord] {
        []
    }
}
