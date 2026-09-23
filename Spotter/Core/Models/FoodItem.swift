import Foundation
import SwiftData

/// A named portion of a food, e.g. "1 slice (28 g)".
struct ServingSize: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    /// Human label shown in the picker, e.g. "1 cup", "1 package", "100 g".
    var label: String
    /// What that portion weighs, in grams. Nutrition is always derived from this.
    var gramWeight: Double

    init(id: UUID = UUID(), label: String, gramWeight: Double) {
        self.id = id
        self.label = label
        self.gramWeight = gramWeight
    }

    /// Every food gets this, so the user can always fall back to weighing.
    static let hundredGrams = ServingSize(label: "100 g", gramWeight: 100)
}

/// A food the user can log: a scanned product, a USDA search result, or one
/// they typed in themselves.
///
/// Nutrition is stored **per 100 g** regardless of source. Both Open Food Facts
/// and USDA expose per-100 g figures, and normalising on ingest means the rest
/// of the app never has to care where a food came from.
@Model
final class FoodItem {
    var id: UUID = UUID()
    var name: String = ""
    var brand: String?

    /// EAN-13 / EAN-8 / UPC. Nil for custom foods and USDA generic entries.
    /// Unique, so re-scanning a product updates the cached row rather than
    /// creating a duplicate.
    @Attribute(.unique) var barcode: String?

    /// Raw value of ``FoodSource`` — see the note in `Enums.swift`.
    var sourceRaw: String = FoodSource.custom.rawValue

    /// Nutrition per 100 g. The single source of truth for this food.
    var nutrientsPer100g: Nutrients = Nutrients.empty

    /// Portions offered in the quantity picker. May be empty; see
    /// ``normalisedServings`` for the display-safe version.
    var servings: [ServingSize] = []

    var isCustom: Bool = false
    var createdAt: Date = Date()

    /// Drives the "Recent" list. Nil until first logged.
    var lastUsedAt: Date?
    /// Drives the "Frequent" list.
    var useCount: Int = 0

    /// Diary entries referencing this food. Deleting a food must NOT delete
    /// history, so the delete rule nullifies the link instead of cascading —
    /// entries carry their own snapshot of name and nutrition.
    @Relationship(deleteRule: .nullify, inverse: \DiaryEntry.food)
    var diaryEntries: [DiaryEntry] = []

    init(
        id: UUID = UUID(),
        name: String,
        brand: String? = nil,
        barcode: String? = nil,
        source: FoodSource = .custom,
        nutrientsPer100g: Nutrients = .empty,
        servings: [ServingSize] = [],
        isCustom: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.barcode = barcode
        self.sourceRaw = source.rawValue
        self.nutrientsPer100g = nutrientsPer100g
        self.servings = servings
        self.isCustom = isCustom
        self.createdAt = createdAt
    }

    var source: FoodSource {
        get { FoodSource(rawValue: sourceRaw) ?? .custom }
        set { sourceRaw = newValue.rawValue }
    }

    /// Servings with a 100 g option guaranteed present.
    var normalisedServings: [ServingSize] {
        var result = servings
        if !result.contains(where: { $0.gramWeight == 100 }) {
            result.append(.hundredGrams)
        }
        return result
    }

    /// The portion to preselect in the quantity picker: the source's own
    /// serving if it declared one, otherwise 100 g.
    var defaultServing: ServingSize {
        servings.first ?? .hundredGrams
    }

    /// Name with brand, for list rows: "Weet-Bix · Sanitarium".
    var displayTitle: String {
        guard let brand, !brand.isEmpty else { return name }
        return "\(name) · \(brand)"
    }

    /// Nutrition for `quantity` of `serving`.
    func nutrients(quantity: Double, serving: ServingSize) -> Nutrients {
        nutrientsPer100g.scaled(byGrams: serving.gramWeight * quantity)
    }

    /// Record that this food was logged, so it surfaces in Recents/Frequents.
    func markUsed(at date: Date = Date()) {
        lastUsedAt = date
        useCount += 1
    }
}
