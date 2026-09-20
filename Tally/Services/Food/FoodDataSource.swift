import Foundation

/// A food as returned by a remote source, before it becomes a `FoodItem`.
///
/// This is a plain transport value, deliberately separate from the SwiftData
/// model. Networking code can therefore be written and tested with no store at
/// all, and a lookup that returns nothing useful never leaves a half-populated
/// row behind in the database.
struct FoodRecord: Hashable, Identifiable, Sendable {
    /// Stable identifier from the source: a barcode for Open Food Facts, an
    /// FDC ID for USDA. Used to deduplicate cached results.
    var sourceID: String
    var source: FoodSource
    var name: String
    var brand: String?
    var barcode: String?
    /// Nutrition per 100 g. Sources that only publish per-serving figures are
    /// normalised to this by their client before the record is constructed.
    var nutrientsPer100g: Nutrients
    /// Portions the source declared. May be empty.
    var servings: [ServingSize]
    /// Product thumbnail, when the source has one.
    var imageURL: URL?

    var id: String { "\(source.rawValue):\(sourceID)" }

    init(
        sourceID: String,
        source: FoodSource,
        name: String,
        brand: String? = nil,
        barcode: String? = nil,
        nutrientsPer100g: Nutrients,
        servings: [ServingSize] = [],
        imageURL: URL? = nil
    ) {
        self.sourceID = sourceID
        self.source = source
        self.name = name
        self.brand = brand
        self.barcode = barcode
        self.nutrientsPer100g = nutrientsPer100g
        self.servings = servings
        self.imageURL = imageURL
    }

    /// True when the record has no usable energy figure.
    ///
    /// Worth checking before offering a record for logging: Open Food Facts
    /// contains a great many products with a name and a photo but no nutrition
    /// panel, and logging one silently contributes nothing to the day's total.
    var lacksNutrition: Bool { nutrientsPer100g.effectiveKcal == nil }

    /// Convert to a persistable model.
    func makeFoodItem() -> FoodItem {
        FoodItem(
            name: name,
            brand: brand,
            barcode: barcode,
            source: source,
            nutrientsPer100g: nutrientsPer100g,
            servings: servings,
            isCustom: false
        )
    }
}

/// What can go wrong looking a food up.
///
/// `productNotFound` is separated from the transport failures on purpose: it is
/// the single most common outcome of scanning a barcode — Open Food Facts is
/// crowd-sourced and simply does not have every product — and the UI answers it
/// by offering manual entry rather than by showing an error.
enum FoodDataError: Error, Equatable, Sendable {
    /// The source has no record for this barcode or query.
    case productNotFound
    /// No network, or the request timed out.
    case offline
    /// The source answered, but not with anything we could parse.
    case decodingFailed(String)
    /// Rate limited. Open Food Facts allows 15 product reads per minute per IP.
    case rateLimited
    /// The source requires a key that has not been configured. USDA search is
    /// disabled rather than broken when no key is present.
    case missingAPIKey
    /// Any other server-side failure, carrying the HTTP status.
    case serverError(status: Int)

    /// Message suitable for showing to the user.
    var userMessage: String {
        switch self {
        case .productNotFound:
            "We couldn't find that product."
        case .offline:
            "No internet connection."
        case .decodingFailed:
            "That product's data couldn't be read."
        case .rateLimited:
            "Too many lookups just now — wait a moment and try again."
        case .missingAPIKey:
            "Food search isn't configured. Add a USDA API key in Settings."
        case .serverError(let status):
            "The food database is unavailable (error \(status))."
        }
    }

    /// Whether retrying the same request might succeed.
    var isRetryable: Bool {
        switch self {
        case .offline, .rateLimited, .serverError: true
        case .productNotFound, .decodingFailed, .missingAPIKey: false
        }
    }
}

/// A source of food data.
///
/// Feature code depends on this protocol, never on a concrete client, so the
/// UI can be built and previewed against ``MockFoodDataSource`` while the real
/// networking is written independently.
protocol FoodDataSource: Sendable {
    /// Look up a single product by barcode.
    ///
    /// - Throws: ``FoodDataError/productNotFound`` when the source has no such
    ///   product. Callers are expected to handle that case as a normal outcome.
    func product(barcode: String) async throws -> FoodRecord

    /// Free-text search.
    ///
    /// - Parameter page: 1-based. Sources that cannot paginate ignore it and
    ///   return an empty array for pages beyond the first.
    /// - Returns: possibly empty. An empty result is not an error.
    func search(query: String, page: Int) async throws -> [FoodRecord]
}

extension FoodDataSource {
    /// Search the first page.
    func search(query: String) async throws -> [FoodRecord] {
        try await search(query: query, page: 1)
    }
}
