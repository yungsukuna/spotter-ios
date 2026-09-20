import Foundation

// Wire-format types for USDA FoodData Central's `/v1/foods/search` endpoint.

/// Search response envelope. USDA also returns `totalHits`/`currentPage`
/// fields the app does not need, so they are simply not declared here.
struct USDASearchResponse: Decodable {
    let foods: [USDAFood]

    private enum CodingKeys: String, CodingKey {
        case foods
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        foods = (try? container.decodeIfPresent([USDAFood].self, forKey: .foods)) ?? []
    }
}

/// A single food as returned by search. Branded-food nutrient values on this
/// endpoint are per 100 g already; `servingSize`/`servingSizeUnit` describe a
/// portion on top of that, they do not change what `foodNutrients` means.
struct USDAFood: Decodable {
    let fdcId: Int
    let description: String
    let brandOwner: String?
    let brandName: String?
    /// Barcode, when the record is a branded food that declared one.
    let gtinUpc: String?
    let servingSize: Double?
    let servingSizeUnit: String?
    let foodNutrients: [USDAFoodNutrient]

    private enum CodingKeys: String, CodingKey {
        case fdcId, description, brandOwner, brandName, gtinUpc
        case servingSize, servingSizeUnit, foodNutrients
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fdcId = container.lenientInt(forKey: .fdcId) ?? 0
        description = container.lenientString(forKey: .description) ?? "Unknown food"
        brandOwner = container.lenientString(forKey: .brandOwner)
        brandName = container.lenientString(forKey: .brandName)
        gtinUpc = container.lenientString(forKey: .gtinUpc)
        servingSize = container.lenientDouble(forKey: .servingSize)
        servingSizeUnit = container.lenientString(forKey: .servingSizeUnit)
        foodNutrients = (try? container.decodeIfPresent([USDAFoodNutrient].self, forKey: .foodNutrients)) ?? []
    }
}

/// One entry of a food's `foodNutrients` array.
///
/// Handled defensively because two different shapes exist across FDC
/// endpoints: the search endpoint used here returns a flat object with
/// `nutrientId`/`nutrientNumber`/`value`, while the single-food detail
/// endpoint nests an object under `nutrient` with `amount` alongside it. Both
/// are decoded into the same `id`/`value` pair so the mapping code in
/// ``USDAFoodDataCentralClient`` does not need to know which shape it got.
struct USDAFoodNutrient: Decodable {
    /// FDC's numeric nutrient ID (1008 = energy kcal, 1003 = protein, etc.),
    /// resolved from whichever field carried it.
    let id: Int?
    let value: Double?

    private enum CodingKeys: String, CodingKey {
        case nutrientId, nutrientNumber, value, amount, nutrient
    }

    private struct NestedNutrient: Decodable {
        let id: Int?
        let number: String?

        private enum CodingKeys: String, CodingKey { case id, number }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = container.lenientInt(forKey: .id)
            number = container.lenientString(forKey: .number)
        }
    }

    /// Legacy "nutrient number" (the SR/pre-FDC numbering, e.g. "203" for
    /// protein) mapped to the modern nutrient ID this app maps by, for the
    /// rare record that carries a number but no ID on either shape.
    private static let legacyNumberToID: [String: Int] = [
        "208": 1008, // Energy, kcal
        "203": 1003, // Protein
        "204": 1004, // Total lipid (fat)
        "205": 1005, // Carbohydrate, by difference
        "291": 1079, // Fiber, total dietary
        "269": 2000, // Total Sugars
        "307": 1093, // Sodium
        "606": 1258, // Fatty acids, total saturated
    ]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Decoded once, explicitly `Optional`, and never allowed to throw:
        // absence of a nested `nutrient` object (the flat search-endpoint
        // shape) is exactly as expected as its presence (the detail-endpoint
        // shape), so this must not fail the whole nutrient entry either way.
        var nestedNutrient: NestedNutrient?
        if container.contains(.nutrient) {
            nestedNutrient = try? container.decode(NestedNutrient.self, forKey: .nutrient)
        }

        if let flatID = container.lenientInt(forKey: .nutrientId) {
            id = flatID
        } else if let nestedID = nestedNutrient?.id {
            id = nestedID
        } else if let number = container.lenientString(forKey: .nutrientNumber),
                  let mapped = Self.legacyNumberToID[number] {
            id = mapped
        } else if let number = nestedNutrient?.number,
                  let mapped = Self.legacyNumberToID[number] {
            id = mapped
        } else {
            id = nil
        }

        if let flatValue = container.lenientDouble(forKey: .value) {
            value = flatValue
        } else {
            value = container.lenientDouble(forKey: .amount)
        }
    }
}
