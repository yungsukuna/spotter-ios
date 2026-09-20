import Foundation
import SwiftData
import Testing

@testable import Tally

/// A fake ``FoodDataSource`` that counts calls and returns a stubbed result,
/// so tests can assert the network was (or was not) touched without any real
/// networking. Mirrors ``MockFoodDataSource``'s `@unchecked Sendable` shape.
private final class CountingFoodDataSource: FoodDataSource, @unchecked Sendable {
    private(set) var productCallCount = 0
    private(set) var searchCallCount = 0
    var recordToReturn: FoodRecord?
    var errorToThrow: FoodDataError?

    func product(barcode: String) async throws -> FoodRecord {
        productCallCount += 1
        if let errorToThrow { throw errorToThrow }
        guard let recordToReturn else { throw FoodDataError.productNotFound }
        return recordToReturn
    }

    func search(query: String, page: Int) async throws -> [FoodRecord] {
        searchCallCount += 1
        return []
    }
}

/// ``CachingFoodRepository`` is what keeps repeat scans instant, offline, and
/// comfortably under Open Food Facts' rate limit — these tests exist to
/// prove the cache actually shields the network, not just that the code
/// compiles.
@MainActor
@Suite("CachingFoodRepository")
struct CachingFoodRepositoryTests {

    private func makeContext() throws -> ModelContext {
        let container = try TallySchema.makeContainer(inMemory: true)
        return ModelContext(container)
    }

    @Test("A cached barcode is returned without ever calling the remote source")
    func cacheHitSkipsNetwork() async throws {
        let context = try makeContext()
        let cached = FoodItem(
            name: "Already Cached",
            barcode: "123456789012",
            source: .openFoodFacts,
            nutrientsPer100g: Nutrients(kcal: 250)
        )
        context.insert(cached)
        try context.save()

        let remote = CountingFoodDataSource()
        let repository = CachingFoodRepository(remote: remote, context: context)

        let result = try await repository.product(barcode: "123456789012")

        #expect(result.name == "Already Cached")
        #expect(remote.productCallCount == 0)
    }

    @Test("A cache miss fetches from the remote source and persists the result")
    func cacheMissFetchesAndPersists() async throws {
        let context = try makeContext()
        let remote = CountingFoodDataSource()
        remote.recordToReturn = FoodRecord(
            sourceID: "9999999999999",
            source: .openFoodFacts,
            name: "Freshly Fetched",
            barcode: "9999999999999",
            nutrientsPer100g: Nutrients(kcal: 150)
        )
        let repository = CachingFoodRepository(remote: remote, context: context)

        let result = try await repository.product(barcode: "9999999999999")

        #expect(result.name == "Freshly Fetched")
        #expect(remote.productCallCount == 1)

        let stored = try context.fetch(
            FetchDescriptor<FoodItem>(predicate: #Predicate<FoodItem> { $0.barcode == "9999999999999" })
        )
        #expect(stored.count == 1)
    }

    @Test("A remote productNotFound propagates on a cache miss rather than being swallowed")
    func remoteErrorPropagatesOnCacheMiss() async throws {
        let context = try makeContext()
        let remote = CountingFoodDataSource()
        let repository = CachingFoodRepository(remote: remote, context: context)

        let error = try await #require(throws: FoodDataError.self) {
            try await repository.product(barcode: "0000000000000")
        }
        #expect(error == .productNotFound)
    }

    @Test("store() updates the existing cached row instead of inserting a duplicate")
    func storeUpdatesExistingRowByBarcode() throws {
        let context = try makeContext()
        let repository = CachingFoodRepository(remote: CountingFoodDataSource(), context: context)

        let first = FoodRecord(
            sourceID: "1", source: .openFoodFacts, name: "First Name",
            barcode: "777", nutrientsPer100g: Nutrients(kcal: 100)
        )
        _ = try repository.store(first)

        let second = FoodRecord(
            sourceID: "1", source: .openFoodFacts, name: "Updated Name",
            barcode: "777", nutrientsPer100g: Nutrients(kcal: 200)
        )
        _ = try repository.store(second)

        let items = try context.fetch(FetchDescriptor<FoodItem>(predicate: #Predicate<FoodItem> { $0.barcode == "777" }))
        #expect(items.count == 1)
        #expect(items.first?.name == "Updated Name")
        #expect(items.first?.nutrientsPer100g.kcal == 200)
    }

    @Test("store() never overwrites a user's custom edits with remote data")
    func storeNeverOverwritesCustomEdits() throws {
        let context = try makeContext()
        let repository = CachingFoodRepository(remote: CountingFoodDataSource(), context: context)

        let custom = FoodItem(
            name: "My Homemade Chili",
            barcode: "555",
            source: .custom,
            nutrientsPer100g: Nutrients(kcal: 180),
            isCustom: true
        )
        context.insert(custom)
        try context.save()

        let incoming = FoodRecord(
            sourceID: "1", source: .openFoodFacts, name: "Remote Chili",
            barcode: "555", nutrientsPer100g: Nutrients(kcal: 999)
        )
        let result = try repository.store(incoming)

        #expect(result.name == "My Homemade Chili")
        #expect(result.nutrientsPer100g.kcal == 180)

        let items = try context.fetch(FetchDescriptor<FoodItem>(predicate: #Predicate<FoodItem> { $0.barcode == "555" }))
        #expect(items.count == 1)
    }

    @Test("Search always calls the remote source and does not touch the cache")
    func searchAlwaysHitsRemote() async throws {
        let context = try makeContext()
        let remote = CountingFoodDataSource()
        let repository = CachingFoodRepository(remote: remote, context: context)

        _ = try await repository.search(query: "noodles")
        #expect(remote.searchCallCount == 1)
    }
}
