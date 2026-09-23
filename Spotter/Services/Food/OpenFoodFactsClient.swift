import Foundation

/// ``FoodDataSource`` backed by [Open Food Facts](https://world.openfoodfacts.org).
///
/// The primary source for barcode scanning — see the README's "Data sources
/// and attribution" section for the licensing obligations that come with
/// using it. Two API rules are enforced here and must not be removed without
/// re-reading that section first:
///
/// 1. **A descriptive `User-Agent` is required.** Anonymous traffic can be
///    refused outright, so every request carries one built from
///    ``AppConfiguration/openFoodFactsUserAgent(contact:)``.
/// 2. **15 product reads per minute per IP** (10/min for search). Exceeding
///    this can get the app blocked entirely, so both operations go through a
///    local ``RateLimiter`` that throws ``FoodDataError/rateLimited`` instead
///    of ever sending the request that would trip the server-side limit.
///
/// An actor: the rate limiter's internal state must not be mutated from two
/// concurrent lookups at once, and actor isolation gets that for free.
actor OpenFoodFactsClient: FoodDataSource {

    private let session: URLSession
    private let userAgent: String
    private let productRateLimiter: RateLimiter
    private let searchRateLimiter: RateLimiter

    /// - Parameter contact: Passed straight to
    ///   ``AppConfiguration/openFoodFactsUserAgent(contact:)`` — typically a
    ///   support email or repo URL identifying this deployment of the app.
    init(contact: String = "", session: URLSession = .shared) {
        self.session = session
        self.userAgent = AppConfiguration.openFoodFactsUserAgent(contact: contact)
        self.productRateLimiter = RateLimiter(maxRequests: 15, windowSeconds: 60)
        self.searchRateLimiter = RateLimiter(maxRequests: 10, windowSeconds: 60)
    }

    // MARK: - FoodDataSource

    func product(barcode: String) async throws -> FoodRecord {
        try await productRateLimiter.acquireOrThrow()

        let fields = "code,product_name,brands,quantity,serving_size,serving_quantity,nutriments,image_front_small_url"
        var components = URLComponents(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json")
        components?.queryItems = [URLQueryItem(name: "fields", value: fields)]
        guard let url = components?.url else {
            throw FoodDataError.decodingFailed("Could not build product URL for barcode \(barcode)")
        }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let data = try await perform(request)
        return try Self.parseProduct(barcode: barcode, data: data)
    }

    func search(query: String, page: Int) async throws -> [FoodRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        try await searchRateLimiter.acquireOrThrow()

        let fields = "code,product_name,brands,quantity,serving_size,serving_quantity,nutriments,image_front_small_url"
        var components = URLComponents(string: "https://world.openfoodfacts.org/cgi/search.pl")
        components?.queryItems = [
            URLQueryItem(name: "search_terms", value: trimmed),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "page_size", value: "20"),
            URLQueryItem(name: "fields", value: fields),
        ]
        guard let url = components?.url else {
            throw FoodDataError.decodingFailed("Could not build search URL for query \(query)")
        }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let data = try await perform(request)
        return try Self.parseSearch(data: data)
    }

    // MARK: - Networking

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await fetch(request)
        try Self.validate(response)
        return data
    }

    /// Split out so tests never need a live network call: everything above
    /// this line is exercised through ``parseProduct(barcode:data:)`` and
    /// ``parseSearch(data:)`` directly against fixture JSON.
    private func fetch(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw FoodDataError.offline
        }
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 429 {
            throw FoodDataError.rateLimited
        }
        guard (200...299).contains(http.statusCode) else {
            throw FoodDataError.serverError(status: http.statusCode)
        }
    }

    // MARK: - Parsing (network-free, unit tested directly)

    static func parseProduct(barcode: String, data: Data) throws -> FoodRecord {
        let decoded: OFFProductResponse
        do {
            decoded = try JSONDecoder().decode(OFFProductResponse.self, from: data)
        } catch {
            throw FoodDataError.decodingFailed(String(describing: error))
        }
        guard decoded.status == 1, let product = decoded.product else {
            throw FoodDataError.productNotFound
        }
        return makeRecord(barcode: barcode, product: product)
    }

    static func parseSearch(data: Data) throws -> [FoodRecord] {
        let decoded: OFFSearchResponse
        do {
            decoded = try JSONDecoder().decode(OFFSearchResponse.self, from: data)
        } catch {
            throw FoodDataError.decodingFailed(String(describing: error))
        }
        return decoded.products.map { makeRecord(barcode: $0.code, product: $0) }
    }

    // MARK: - Mapping

    static func makeRecord(barcode: String?, product: OFFProduct) -> FoodRecord {
        let sourceID = product.code ?? barcode ?? UUID().uuidString
        let name = product.productName ?? "Unknown product"
        return FoodRecord(
            sourceID: sourceID,
            source: .openFoodFacts,
            name: name,
            brand: product.brands,
            barcode: barcode ?? product.code,
            nutrientsPer100g: makeNutrients(from: product.nutriments),
            servings: makeServings(from: product),
            imageURL: product.imageFrontSmallURL.flatMap(URL.init(string:))
        )
    }

    /// Missing nutrition is the norm on this API, not an error — a product
    /// with no panel maps to `Nutrients.empty` here rather than failing the
    /// whole lookup, and ``FoodRecord/lacksNutrition`` is what routes it to
    /// manual entry in the UI.
    static func makeNutrients(from nutriments: OFFNutriments?) -> Nutrients {
        guard let nutriments else { return .empty }
        return Nutrients(
            // If energy is absent but macros are present, leave `kcal` nil —
            // `Nutrients.effectiveKcal` already falls back to the Atwater
            // estimate from the macros, so no estimate is computed here.
            kcal: nutriments.energyKcal100g,
            proteinG: nutriments.proteins100g,
            carbsG: nutriments.carbohydrates100g,
            fatG: nutriments.fat100g,
            satFatG: nutriments.saturatedFat100g,
            sugarG: nutriments.sugars100g,
            fiberG: nutriments.fiber100g,
            sodiumMG: sodiumMG(from: nutriments)
        )
    }

    /// Sodium, in mg. OFF's own `sodium_100g` (grams) is preferred when
    /// present; otherwise sodium is derived from salt, which every OFF
    /// product is far more likely to have: salt is 2.5x sodium by mass, so
    /// grams of sodium is `salt / 2.5`, then x1000 for mg.
    static func sodiumMG(from nutriments: OFFNutriments) -> Double? {
        if let sodiumG = nutriments.sodium100g {
            return sodiumG * 1000
        }
        if let saltG = nutriments.salt100g {
            return (saltG / 2.5) * 1000
        }
        return nil
    }

    /// Builds the source-declared serving, in grams, from `serving_size` (the
    /// human label) and `serving_quantity` (the gram weight). Both must be
    /// usable, or no serving is offered — ``FoodItem/normalisedServings``
    /// always adds a 100 g fallback regardless.
    static func makeServings(from product: OFFProduct) -> [ServingSize] {
        guard let grams = product.servingQuantity, grams > 0 else { return [] }
        let label = product.servingSize ?? "\(trimmedNumber(grams)) g"
        return [ServingSize(label: label, gramWeight: grams)]
    }

    /// "52" / "0.3" — trims a whole-number gram value to an integer, keeps
    /// one decimal place otherwise. Only used to synthesise a label when the
    /// source gave a gram weight but no human-readable serving text.
    static func trimmedNumber(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(value))
            : String(format: "%.1f", value)
    }
}
