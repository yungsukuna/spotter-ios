import Foundation
import Testing

@testable import Spotter

/// Decoding and mapping tests for ``USDAFoodDataCentralClient``.
///
/// Like the Open Food Facts tests, these decode embedded JSON fixtures
/// directly through `parseSearch` rather than hitting the network.
@Suite("USDAFoodDataCentralClient")
struct USDAFoodDataCentralClientTests {

    static let completeSearchJSON = """
    {
      "totalHits": 1,
      "foods": [
        {
          "fdcId": 748967,
          "description": "Chicken breast, raw",
          "brandOwner": "Acme Foods",
          "gtinUpc": "012345678905",
          "servingSize": 84,
          "servingSizeUnit": "g",
          "foodNutrients": [
            { "nutrientId": 1008, "nutrientName": "Energy", "nutrientNumber": "208", "unitName": "KCAL", "value": 120 },
            { "nutrientId": 1003, "nutrientName": "Protein", "nutrientNumber": "203", "unitName": "G", "value": 22.5 },
            { "nutrientId": 1004, "nutrientName": "Total lipid (fat)", "nutrientNumber": "204", "unitName": "G", "value": 2.6 },
            { "nutrientId": 1005, "nutrientName": "Carbohydrate, by difference", "nutrientNumber": "205", "unitName": "G", "value": 0 },
            { "nutrientId": 1079, "nutrientName": "Fiber, total dietary", "nutrientNumber": "291", "unitName": "G", "value": 0 },
            { "nutrientId": 2000, "nutrientName": "Total Sugars", "nutrientNumber": "269", "unitName": "G", "value": 0 },
            { "nutrientId": 1093, "nutrientName": "Sodium, Na", "nutrientNumber": "307", "unitName": "MG", "value": 45 },
            { "nutrientId": 1258, "nutrientName": "Fatty acids, total saturated", "nutrientNumber": "606", "unitName": "G", "value": 0.6 }
          ]
        }
      ]
    }
    """

    static let missingNutrientsSearchJSON = """
    {
      "totalHits": 1,
      "foods": [
        {
          "fdcId": 111111,
          "description": "Mystery Snack Bar",
          "foodNutrients": []
        }
      ]
    }
    """

    @Test("A complete search result decodes name, brand, barcode and every mapped nutrient")
    func decodesCompleteFood() throws {
        let data = Self.completeSearchJSON.data(using: .utf8)!
        let records = try USDAFoodDataCentralClient.parseSearch(data: data)
        let record = try #require(records.first)

        #expect(record.name == "Chicken breast, raw")
        #expect(record.brand == "Acme Foods")
        #expect(record.barcode == "012345678905")
        #expect(record.source == .usda)
        #expect(record.nutrientsPer100g.kcal == 120)
        #expect(record.nutrientsPer100g.proteinG == 22.5)
        #expect(record.nutrientsPer100g.fatG == 2.6)
        #expect(record.nutrientsPer100g.sodiumMG == 45)
        #expect(record.nutrientsPer100g.satFatG == 0.6)
    }

    @Test("servingSize + servingSizeUnit in grams builds a serving directly")
    func buildsServingInGrams() throws {
        let data = Self.completeSearchJSON.data(using: .utf8)!
        let record = try #require(try USDAFoodDataCentralClient.parseSearch(data: data).first)

        let serving = try #require(record.servings.first)
        #expect(serving.gramWeight == 84)
    }

    @Test("A food with an empty foodNutrients array produces empty nutrition, not an error")
    func missingNutrientsIsEmptyNotAnError() throws {
        let data = Self.missingNutrientsSearchJSON.data(using: .utf8)!
        let record = try #require(try USDAFoodDataCentralClient.parseSearch(data: data).first)

        #expect(record.nutrientsPer100g.isEmpty)
        #expect(record.lacksNutrition)
        #expect(record.name == "Mystery Snack Bar")
    }

    @Test("An empty foods array decodes to an empty list, not an error")
    func emptyFoodsArrayIsNotAnError() throws {
        let data = "{ \"foods\": [] }".data(using: .utf8)!
        let records = try USDAFoodDataCentralClient.parseSearch(data: data)
        #expect(records.isEmpty)
    }

    @Test("A nutrient entry with only the legacy nutrientNumber still maps by the modern ID")
    func legacyNutrientNumberMapsToModernID() throws {
        let json = """
        {
          "foods": [
            {
              "fdcId": 1,
              "description": "Legacy Numbered Food",
              "foodNutrients": [
                { "nutrientNumber": "208", "value": 200 },
                { "nutrientNumber": "203", "value": 15 }
              ]
            }
          ]
        }
        """
        let data = json.data(using: .utf8)!
        let record = try #require(try USDAFoodDataCentralClient.parseSearch(data: data).first)

        #expect(record.nutrientsPer100g.kcal == 200)
        #expect(record.nutrientsPer100g.proteinG == 15)
    }

    @Test("A nested nutrient/amount shape (the food-detail endpoint's shape) still decodes")
    func nestedNutrientShapeDecodes() throws {
        let json = """
        {
          "foods": [
            {
              "fdcId": 2,
              "description": "Nested Shape Food",
              "foodNutrients": [
                { "nutrient": { "id": 1008, "number": "208" }, "amount": 250 }
              ]
            }
          ]
        }
        """
        let data = json.data(using: .utf8)!
        let record = try #require(try USDAFoodDataCentralClient.parseSearch(data: data).first)

        #expect(record.nutrientsPer100g.kcal == 250)
    }

    // MARK: - Missing API key

    @Test("With no USDA key configured, search throws missingAPIKey before any request")
    func searchThrowsMissingAPIKeyWithNoKey() async throws {
        // The test bundle ships no USDAAPIKey (Secrets.xcconfig is gitignored
        // and never present in CI), so AppConfiguration.usdaAPIKey is nil
        // here exactly as it would be on a fresh clone — this is the real
        // "no key configured" path, not a stand-in for it.
        guard AppConfiguration.usdaAPIKey == nil else {
            // A developer running locally with Secrets.xcconfig configured
            // would otherwise see this test fail for the wrong reason.
            return
        }
        let client = USDAFoodDataCentralClient()
        let error = try await #require(throws: FoodDataError.self) {
            try await client.search(query: "chicken", page: 1)
        }
        #expect(error == .missingAPIKey)
    }

    @Test("With no USDA key configured, product(barcode:) throws missingAPIKey before any request")
    func productThrowsMissingAPIKeyWithNoKey() async throws {
        guard AppConfiguration.usdaAPIKey == nil else { return }
        let client = USDAFoodDataCentralClient()
        let error = try await #require(throws: FoodDataError.self) {
            try await client.product(barcode: "737628064502")
        }
        #expect(error == .missingAPIKey)
    }
}
