import Foundation

/// ``FoodDataSource`` backed by [USDA FoodData Central](https://fdc.nal.usda.gov/).
///
/// The primary source for generic-food text search — OFF's search is weak
/// for anything that is not a specific packaged product, whereas FDC's
/// branded + standard-reference database is exactly the "chicken breast,
/// raw" case OFF struggles with.
///
/// Barcode lookup is a thin, best-effort addition here: FDC's branded foods
/// sometimes carry a `gtinUpc`, so `product(barcode:)` searches by barcode
/// text and matches it exactly against that field. Open Food Facts remains
/// the primary and far more reliable barcode source; see
/// ``CompositeFoodDataSource``, which only falls back to this method after
/// OFF reports the product unknown.
///
/// An actor purely for consistency with ``OpenFoodFactsClient`` and to keep
/// the door open for local state (e.g. a future response cache) without a
/// later refactor.
actor USDAFoodDataCentralClient: FoodDataSource {

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - FoodDataSource

    /// - Throws: ``FoodDataError/missingAPIKey`` immediately, before any
    ///   request is sent, when no USDA key is configured. The app must work
    ///   with USDA search simply disabled rather than erroring on every food
    ///   lookup for a user who never signed up for a key.
    func product(barcode: String) async throws -> FoodRecord {
        let results = try await performSearch(query: barcode, page: 1)
        guard let match = results.first(where: { $0.barcode == barcode }) else {
            throw FoodDataError.productNotFound
        }
        return match
    }

    func search(query: String, page: Int) async throws -> [FoodRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return try await performSearch(query: trimmed, page: page)
    }

    // MARK: - Networking

    private func performSearch(query: String, page: Int) async throws -> [FoodRecord] {
        guard let apiKey = AppConfiguration.usdaAPIKey else {
            throw FoodDataError.missingAPIKey
        }

        var components = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/foods/search")
        components?.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "pageSize", value: "25"),
            URLQueryItem(name: "pageNumber", value: String(page)),
        ]
        guard let url = components?.url else {
            throw FoodDataError.decodingFailed("Could not build USDA search URL")
        }

        let data = try await fetch(URLRequest(url: url))
        return try Self.parseSearch(data: data)
    }

    /// Split out so tests never need a live network call — see
    /// ``parseSearch(data:)``.
    private func fetch(_ request: URLRequest) async throws -> Data {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw FoodDataError.offline
        }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            if http.statusCode == 429 {
                throw FoodDataError.rateLimited
            }
            throw FoodDataError.serverError(status: http.statusCode)
        }
        return data
    }

    // MARK: - Parsing (network-free, unit tested directly)

    static func parseSearch(data: Data) throws -> [FoodRecord] {
        let decoded: USDASearchResponse
        do {
            decoded = try JSONDecoder().decode(USDASearchResponse.self, from: data)
        } catch {
            throw FoodDataError.decodingFailed(String(describing: error))
        }
        return decoded.foods.map(makeRecord)
    }

    // MARK: - Mapping

    static func makeRecord(from food: USDAFood) -> FoodRecord {
        FoodRecord(
            sourceID: String(food.fdcId),
            source: .usda,
            name: food.description,
            brand: food.brandOwner ?? food.brandName,
            barcode: food.gtinUpc,
            nutrientsPer100g: makeNutrients(from: food.foodNutrients),
            servings: makeServings(from: food)
        )
    }

    /// FDC nutrient IDs used to pull values out of the flat `foodNutrients`
    /// array. These are the modern FDC IDs, not the legacy SR "nutrient
    /// number" scheme (see `USDAModels.swift`).
    private enum NutrientID {
        static let energyKcal = 1008
        static let protein = 1003
        static let fat = 1004
        static let carbohydrate = 1005
        static let fiber = 1079
        static let totalSugars = 2000
        static let sodium = 1093
        static let saturatedFat = 1258
    }

    /// Branded-food values from this endpoint are already per 100 g, so no
    /// scaling happens here — only picking each nutrient out by ID.
    static func makeNutrients(from nutrients: [USDAFoodNutrient]) -> Nutrients {
        func value(for id: Int) -> Double? {
            nutrients.first(where: { $0.id == id })?.value
        }
        return Nutrients(
            kcal: value(for: NutrientID.energyKcal),
            proteinG: value(for: NutrientID.protein),
            carbsG: value(for: NutrientID.carbohydrate),
            fatG: value(for: NutrientID.fat),
            satFatG: value(for: NutrientID.saturatedFat),
            sugarG: value(for: NutrientID.totalSugars),
            fiberG: value(for: NutrientID.fiber),
            sodiumMG: value(for: NutrientID.sodium)
        )
    }

    /// Builds a serving from `servingSize` + `servingSizeUnit`, converting to
    /// grams. Units this app cannot convert with confidence (anything but
    /// grams, ounces, or millilitres treated as water-density) are dropped
    /// rather than guessed at.
    static func makeServings(from food: USDAFood) -> [ServingSize] {
        guard let size = food.servingSize, size > 0 else { return [] }
        let unit = (food.servingSizeUnit ?? "g").lowercased()
        let grams: Double?
        switch unit {
        case "g", "grm", "gram", "grams":
            grams = size
        case "oz", "ounce", "ounces":
            grams = size * 28.3495
        case "ml", "milliliter", "milliliters", "millilitre", "millilitres":
            // FDC does not publish density; treating millilitres as grams is
            // a rough but reasonable approximation for near-water-density
            // liquids, and better than discarding the serving entirely.
            grams = size
        default:
            grams = nil
        }
        guard let grams else { return [] }
        let label = "\(trimmedNumber(size)) \(food.servingSizeUnit ?? "g")"
        return [ServingSize(label: label, gramWeight: grams)]
    }

    /// "30" / "0.3" — mirrors `OpenFoodFactsClient.trimmedNumber`; kept as a
    /// private duplicate rather than a shared helper so this file has no
    /// dependency on that one compiling correctly.
    private static func trimmedNumber(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(value))
            : String(format: "%.1f", value)
    }
}
