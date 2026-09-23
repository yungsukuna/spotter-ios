import Foundation

// Wire-format types for the Open Food Facts API. Kept separate from
// ``FoodRecord`` on purpose — this is the shape OFF actually sends (partial,
// inconsistently typed, keyed by field names with hyphens and underscores),
// and ``OpenFoodFactsClient`` is what translates it into the app's own model.

/// `GET /api/v2/product/{barcode}.json` response envelope.
///
/// `status` is `1` when the barcode was found, `0` otherwise — OFF returns
/// HTTP 200 either way, so this field (not the status code) is what tells the
/// two cases apart.
struct OFFProductResponse: Decodable {
    let status: Int
    let product: OFFProduct?

    private enum CodingKeys: String, CodingKey {
        case status, product
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Defaults to "not found" rather than throwing if `status` itself is
        // ever missing or malformed — an unreadable envelope should read as
        // no product, not as a crash.
        status = container.lenientInt(forKey: .status) ?? 0
        product = try? container.decodeIfPresent(OFFProduct.self, forKey: .product)
    }
}

/// `GET /cgi/search.pl` response envelope. Older endpoint than the v2 barcode
/// lookup, but it is the one that supports free-text search.
struct OFFSearchResponse: Decodable {
    let products: [OFFProduct]

    private enum CodingKeys: String, CodingKey {
        case products
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        products = (try? container.decodeIfPresent([OFFProduct].self, forKey: .products)) ?? []
    }
}

/// A single product as OFF represents it, restricted to the fields requested
/// via `fields=` in the query string.
///
/// Every property here is optional and every field is decoded leniently
/// (see `LenientDecoding.swift`): a name-only, image-only product with no
/// nutrition panel at all is the single most common shape on this API, not a
/// malformed record.
struct OFFProduct: Decodable {
    let code: String?
    let productName: String?
    let brands: String?
    let quantity: String?
    let servingSize: String?
    /// Grams. Documented as a number but observed as a numeric string on some
    /// products — see `LenientDecoding.swift`.
    let servingQuantity: Double?
    let nutriments: OFFNutriments?
    let imageFrontSmallURL: String?

    private enum CodingKeys: String, CodingKey {
        case code
        case productName = "product_name"
        case brands
        case quantity
        case servingSize = "serving_size"
        case servingQuantity = "serving_quantity"
        case nutriments
        case imageFrontSmallURL = "image_front_small_url"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = container.lenientString(forKey: .code)
        productName = container.lenientString(forKey: .productName)
        brands = container.lenientString(forKey: .brands)
        quantity = container.lenientString(forKey: .quantity)
        servingSize = container.lenientString(forKey: .servingSize)
        servingQuantity = container.lenientDouble(forKey: .servingQuantity)
        // `try?` here also swallows the rare case where OFF sends
        // `"nutriments": []` instead of an object for a totally empty panel —
        // that fails to decode as a keyed container and should mean "no
        // panel", not "unreadable product".
        nutriments = try? container.decodeIfPresent(OFFNutriments.self, forKey: .nutriments)
        imageFrontSmallURL = container.lenientString(forKey: .imageFrontSmallURL)
    }
}

/// The subset of OFF's flat `nutriments` dictionary this app uses, per 100 g.
///
/// OFF's own key names mix hyphens and underscores (`energy-kcal_100g`,
/// `saturated-fat_100g`), which is why the `CodingKeys` raw values look
/// inconsistent — they are copied verbatim from the API.
struct OFFNutriments: Decodable {
    let energyKcal100g: Double?
    let proteins100g: Double?
    let carbohydrates100g: Double?
    let fat100g: Double?
    let saturatedFat100g: Double?
    let sugars100g: Double?
    let fiber100g: Double?
    /// Grams of salt per 100 g. Convert to sodium via ``OpenFoodFactsClient``
    /// — do not use this value directly as a nutrient.
    let salt100g: Double?
    /// Grams of sodium per 100 g, when OFF publishes it directly. Preferred
    /// over deriving sodium from `salt100g` when present.
    let sodium100g: Double?

    private enum CodingKeys: String, CodingKey {
        case energyKcal100g = "energy-kcal_100g"
        case proteins100g = "proteins_100g"
        case carbohydrates100g = "carbohydrates_100g"
        case fat100g = "fat_100g"
        case saturatedFat100g = "saturated-fat_100g"
        case sugars100g = "sugars_100g"
        case fiber100g = "fiber_100g"
        case salt100g = "salt_100g"
        case sodium100g = "sodium_100g"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        energyKcal100g = container.lenientDouble(forKey: .energyKcal100g)
        proteins100g = container.lenientDouble(forKey: .proteins100g)
        carbohydrates100g = container.lenientDouble(forKey: .carbohydrates100g)
        fat100g = container.lenientDouble(forKey: .fat100g)
        saturatedFat100g = container.lenientDouble(forKey: .saturatedFat100g)
        sugars100g = container.lenientDouble(forKey: .sugars100g)
        fiber100g = container.lenientDouble(forKey: .fiber100g)
        salt100g = container.lenientDouble(forKey: .salt100g)
        sodium100g = container.lenientDouble(forKey: .sodium100g)
    }

    /// Explicit memberwise initializer — defining `init(from:)` above
    /// suppresses Swift's synthesized one, and tests construct this type
    /// directly to exercise ``OpenFoodFactsClient/makeNutrients(from:)`` and
    /// ``OpenFoodFactsClient/sodiumMG(from:)`` without going through JSON.
    init(
        energyKcal100g: Double? = nil,
        proteins100g: Double? = nil,
        carbohydrates100g: Double? = nil,
        fat100g: Double? = nil,
        saturatedFat100g: Double? = nil,
        sugars100g: Double? = nil,
        fiber100g: Double? = nil,
        salt100g: Double? = nil,
        sodium100g: Double? = nil
    ) {
        self.energyKcal100g = energyKcal100g
        self.proteins100g = proteins100g
        self.carbohydrates100g = carbohydrates100g
        self.fat100g = fat100g
        self.saturatedFat100g = saturatedFat100g
        self.sugars100g = sugars100g
        self.fiber100g = fiber100g
        self.salt100g = salt100g
        self.sodium100g = sodium100g
    }
}
