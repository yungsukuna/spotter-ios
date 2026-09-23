import Foundation
import Testing

@testable import Spotter

/// A spy `FoodDataSource` that records every query it was actually asked to
/// search for — used to verify that rapid typing collapses into one call
/// once debounced, rather than one call per keystroke.
private final class SpyFoodDataSource: FoodDataSource, @unchecked Sendable {
    private(set) var searchedQueries: [String] = []
    var stubbedResult: Result<[FoodRecord], Error> = .success([])

    func product(barcode: String) async throws -> FoodRecord {
        throw FoodDataError.productNotFound
    }

    func search(query: String, page: Int) async throws -> [FoodRecord] {
        searchedQueries.append(query)
        return try stubbedResult.get()
    }
}

@MainActor
@Suite("FoodSearchModel")
struct FoodSearchModelTests {

    @Test("An empty query stays idle and never reaches the data source")
    func emptyQueryStaysIdle() async throws {
        let spy = SpyFoodDataSource()
        let model = FoodSearchModel(dataSource: spy, debounce: .milliseconds(10))

        model.query = "   "
        try await Task.sleep(for: .milliseconds(50))

        #expect(model.phase == .idle)
        #expect(spy.searchedQueries.isEmpty)
    }

    @Test("Rapid edits collapse into a single search for the final text")
    func rapidEditsDebounce() async throws {
        let spy = SpyFoodDataSource()
        let model = FoodSearchModel(dataSource: spy, debounce: .milliseconds(30))

        model.query = "c"
        model.query = "ch"
        model.query = "chi"
        model.query = "chicken"

        try await Task.sleep(for: .milliseconds(150))

        #expect(spy.searchedQueries == ["chicken"])
        #expect(model.phase == .loaded([]))
    }

    @Test("A successful search reports its results")
    func successReportsResults() async throws {
        let spy = SpyFoodDataSource()
        let record = FoodRecord(
            sourceID: "1", source: .usda, name: "Chicken", nutrientsPer100g: Nutrients(kcal: 100)
        )
        spy.stubbedResult = .success([record])
        let model = FoodSearchModel(dataSource: spy, debounce: .milliseconds(10))

        model.query = "chicken"
        try await Task.sleep(for: .milliseconds(60))

        #expect(model.phase == .loaded([record]))
    }

    @Test("A failed search reports the error")
    func failureReportsError() async throws {
        let spy = SpyFoodDataSource()
        spy.stubbedResult = .failure(FoodDataError.offline)
        let model = FoodSearchModel(dataSource: spy, debounce: .milliseconds(10))

        model.query = "chicken"
        try await Task.sleep(for: .milliseconds(60))

        #expect(model.phase == .failed(.offline))
    }

    @Test("Clearing the query after a search cancels back to idle")
    func clearingQueryGoesIdle() async throws {
        let spy = SpyFoodDataSource()
        let model = FoodSearchModel(dataSource: spy, debounce: .milliseconds(10))

        model.query = "chicken"
        try await Task.sleep(for: .milliseconds(60))
        #expect(model.phase == .loaded([]))

        model.query = ""
        #expect(model.phase == .idle)
    }

    @Test("Retry re-runs the current query")
    func retryReRuns() async throws {
        let spy = SpyFoodDataSource()
        spy.stubbedResult = .failure(FoodDataError.offline)
        let model = FoodSearchModel(dataSource: spy, debounce: .milliseconds(10))

        model.query = "chicken"
        try await Task.sleep(for: .milliseconds(60))
        #expect(spy.searchedQueries.count == 1)

        model.retry()
        try await Task.sleep(for: .milliseconds(60))
        #expect(spy.searchedQueries.count == 2)
    }

    @Test("Retry on an empty query does nothing")
    func retryOnEmptyQueryIsNoOp() async throws {
        let spy = SpyFoodDataSource()
        let model = FoodSearchModel(dataSource: spy, debounce: .milliseconds(10))

        model.retry()
        try await Task.sleep(for: .milliseconds(30))

        #expect(spy.searchedQueries.isEmpty)
        #expect(model.phase == .idle)
    }
}
