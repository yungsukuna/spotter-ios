import Foundation
import Testing

@testable import Tally

/// Decoding and mapping tests for ``OpenFoodFactsClient``.
///
/// These go through `OpenFoodFactsClient.parseProduct`/`parseSearch`
/// directly against embedded JSON fixtures rather than making a network
/// call — there is no compiler on this machine to iterate against a live
/// API, so the fixtures are the specification. Each one is drawn from (or
/// modeled closely on) a real response shape called out in the task: a
/// complete product, one with no nutrition panel, one with numeric-string
/// nutriment values, and a not-found response.
@Suite("OpenFoodFactsClient")
struct OpenFoodFactsClientTests {

    // MARK: - Fixtures

    /// Modeled on the real response for barcode 737628064502 (Simply Asia
    /// Thai Peanut Noodle Kit) — a complete product with a serving that is
    /// not a round number of grams.
    static let completeProductJSON = """
    {
      "status": 1,
      "product": {
        "code": "737628064502",
        "product_name": "Thai Peanut Noodle Kit",
        "brands": "Simply Asia",
        "quantity": "156 g",
        "serving_size": "0.333 PACKAGE (52 g)",
        "serving_quantity": 52,
        "nutriments": {
          "energy-kcal_100g": 385,
          "proteins_100g": 9.62,
          "carbohydrates_100g": 71.15,
          "fat_100g": 7.69,
          "saturated-fat_100g": 1.92,
          "sugars_100g": 13.46,
          "fiber_100g": 1.9,
          "salt_100g": 0.72
        },
        "image_front_small_url": "https://images.openfoodfacts.org/thai.jpg"
      }
    }
    """

    /// A product with a name and image but genuinely no nutrition panel —
    /// the single most common awkward shape on this API.
    static let noNutrimentsProductJSON = """
    {
      "status": 1,
      "product": {
        "code": "0000000000000",
        "product_name": "Unlabelled Bakery Item",
        "brands": null,
        "quantity": null,
        "serving_size": null,
        "serving_quantity": null,
        "nutriments": {}
      }
    }
    """

    /// Same nutrient values as the complete fixture, but every numeric
    /// field is sent as a string — observed in the wild on some records.
    static let numericStringNutrimentsJSON = """
    {
      "status": 1,
      "product": {
        "code": "737628064502",
        "product_name": "Thai Peanut Noodle Kit",
        "brands": "Simply Asia",
        "serving_size": "0.333 PACKAGE (52 g)",
        "serving_quantity": "52",
        "nutriments": {
          "energy-kcal_100g": "385",
          "proteins_100g": "9.62",
          "carbohydrates_100g": "71.15",
          "fat_100g": "7.69",
          "salt_100g": "0.72"
        }
      }
    }
    """

    static let notFoundJSON = """
    { "status": 0, "status_verbose": "product not found" }
    """

    // MARK: - Complete product

    @Test("A complete product decodes name, brand, servings and nutrition")
    func decodesCompleteProduct() throws {
        let data = Self.completeProductJSON.data(using: .utf8)!
        let record = try OpenFoodFactsClient.parseProduct(barcode: "737628064502", data: data)

        #expect(record.name == "Thai Peanut Noodle Kit")
        #expect(record.brand == "Simply Asia")
        #expect(record.barcode == "737628064502")
        #expect(record.source == .openFoodFacts)
        #expect(record.nutrientsPer100g.kcal == 385)
        #expect(record.nutrientsPer100g.proteinG == 9.62)
        #expect(record.imageURL?.absoluteString == "https://images.openfoodfacts.org/thai.jpg")
    }

    @Test("The declared serving is built from serving_size and serving_quantity, in grams")
    func buildsServingFromServingQuantity() throws {
        let data = Self.completeProductJSON.data(using: .utf8)!
        let record = try OpenFoodFactsClient.parseProduct(barcode: "737628064502", data: data)

        let serving = try #require(record.servings.first)
        #expect(serving.gramWeight == 52)
        #expect(serving.label == "0.333 PACKAGE (52 g)")
    }

    @Test("Salt is converted to sodium: divide by 2.5, then to mg")
    func saltConvertsToSodium() throws {
        let data = Self.completeProductJSON.data(using: .utf8)!
        let record = try OpenFoodFactsClient.parseProduct(barcode: "737628064502", data: data)

        // 0.72 g salt / 2.5 = 0.288 g sodium = 288 mg.
        let sodium = try #require(record.nutrientsPer100g.sodiumMG)
        #expect(abs(sodium - 288) < 0.001)
    }

    @Test("sodium_100g is preferred over the salt conversion when both are present")
    func sodiumFieldPreferredOverSaltConversion() {
        let nutriments = OFFNutriments(
            energyKcal100g: nil,
            proteins100g: nil,
            carbohydrates100g: nil,
            fat100g: nil,
            saturatedFat100g: nil,
            sugars100g: nil,
            fiber100g: nil,
            salt100g: 1.0,
            sodium100g: 0.5
        )
        // If salt-derived, this would be 400 mg; the direct field must win.
        #expect(OpenFoodFactsClient.sodiumMG(from: nutriments) == 500)
    }

    // MARK: - Missing nutrition

    @Test("A product with no nutriments produces empty nutrition, not an error")
    func missingNutrimentsIsEmptyNotAnError() throws {
        let data = Self.noNutrimentsProductJSON.data(using: .utf8)!
        let record = try OpenFoodFactsClient.parseProduct(barcode: "0000000000000", data: data)

        #expect(record.nutrientsPer100g.isEmpty)
        #expect(record.lacksNutrition)
        #expect(record.name == "Unlabelled Bakery Item")
    }

    @Test("A product with no serving_quantity offers no source-declared serving")
    func missingServingQuantityYieldsNoServings() throws {
        let data = Self.noNutrimentsProductJSON.data(using: .utf8)!
        let record = try OpenFoodFactsClient.parseProduct(barcode: "0000000000000", data: data)

        #expect(record.servings.isEmpty)
    }

    // MARK: - Numeric strings

    @Test("Numeric-string nutriment values decode the same as numbers")
    func numericStringValuesDecode() throws {
        let data = Self.numericStringNutrimentsJSON.data(using: .utf8)!
        let record = try OpenFoodFactsClient.parseProduct(barcode: "737628064502", data: data)

        #expect(record.nutrientsPer100g.kcal == 385)
        #expect(record.nutrientsPer100g.proteinG == 9.62)
        #expect(record.nutrientsPer100g.carbsG == 71.15)
    }

    @Test("A numeric-string serving_quantity still builds a serving in grams")
    func numericStringServingQuantityDecodes() throws {
        let data = Self.numericStringNutrimentsJSON.data(using: .utf8)!
        let record = try OpenFoodFactsClient.parseProduct(barcode: "737628064502", data: data)

        #expect(record.servings.first?.gramWeight == 52)
    }

    @Test("If energy is absent but macros are present, kcal stays nil so Atwater can fill it in")
    func missingEnergyLeavesKcalNilForAtwaterFallback() {
        let nutriments = OFFNutriments(
            energyKcal100g: nil,
            proteins100g: 10,
            carbohydrates100g: 20,
            fat100g: 5,
            saturatedFat100g: nil,
            sugars100g: nil,
            fiber100g: nil,
            salt100g: nil,
            sodium100g: nil
        )
        let nutrients = OpenFoodFactsClient.makeNutrients(from: nutriments)
        #expect(nutrients.kcal == nil)
        // effectiveKcal (from Nutrients.swift) is what fills the gap.
        #expect(nutrients.effectiveKcal == 165)
    }

    // MARK: - Not found

    @Test("status: 0 maps to productNotFound")
    func statusZeroIsProductNotFound() throws {
        let data = Self.notFoundJSON.data(using: .utf8)!
        let error = try #require(throws: FoodDataError.self) {
            try OpenFoodFactsClient.parseProduct(barcode: "0000000000000", data: data)
        }
        #expect(error == .productNotFound)
    }

    // MARK: - Search

    @Test("Search maps every product in the results array")
    func searchMapsAllResults() throws {
        let searchJSON = """
        {
          "products": [
            { "code": "111", "product_name": "First", "nutriments": { "energy-kcal_100g": 100 } },
            { "code": "222", "product_name": "Second", "nutriments": { "energy-kcal_100g": 200 } }
          ]
        }
        """
        let data = searchJSON.data(using: .utf8)!
        let records = try OpenFoodFactsClient.parseSearch(data: data)

        #expect(records.count == 2)
        #expect(records.map(\.name) == ["First", "Second"])
    }

    @Test("An empty search results array decodes to an empty list, not an error")
    func emptySearchResultsIsNotAnError() throws {
        let data = "{ \"products\": [] }".data(using: .utf8)!
        let records = try OpenFoodFactsClient.parseSearch(data: data)
        #expect(records.isEmpty)
    }
}
