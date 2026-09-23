import Foundation
import SwiftData

/// A named group of food items the user logs together often, e.g. "Protein
/// Shake + Oats".
///
/// Items are a Codable value array rather than a child `@Model`, matching how
/// `FoodItem.servings` stores its portions — one new entity instead of two,
/// no inverse relationship to maintain, and nothing that can be orphaned.
/// `SwiftData relationship arrays are unordered` doesn't apply here since this
/// isn't a relationship, but `order` is still kept explicit so reads go
/// through ``orderedItems`` the same way every other ordered list in this app
/// does.
@Model
final class SavedMeal {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    var lastUsedAt: Date?
    var useCount: Int = 0

    /// Raw value of ``Meal``. Nil means "use whichever section was tapped".
    var defaultMealRaw: String?

    var items: [SavedMealItem] = []

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        lastUsedAt: Date? = nil,
        useCount: Int = 0,
        defaultMeal: Meal? = nil,
        items: [SavedMealItem] = []
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.useCount = useCount
        self.defaultMealRaw = defaultMeal?.rawValue
        self.items = items
    }

    var defaultMeal: Meal? {
        get { defaultMealRaw.flatMap(Meal.init(rawValue:)) }
        set { defaultMealRaw = newValue?.rawValue }
    }

    /// Items in display order. Always read through this — see the ordering
    /// note in `Workout.swift`, which applies here even though this isn't a
    /// SwiftData relationship.
    var orderedItems: [SavedMealItem] {
        items.sorted { $0.order < $1.order }
    }

    /// Sum of every item's snapshot nutrition. Unknown values stay unknown —
    /// `Nutrients.total` only treats a value as zero when at least one item
    /// actually reports it.
    var totalNutrients: Nutrients {
        Nutrients.total(of: items.map(\.nutrientsSnapshot))
    }

    /// Record that this meal was logged, so it can surface as a Frequent.
    func markUsed(at date: Date = Date()) {
        lastUsedAt = date
        useCount += 1
    }
}

/// One food within a ``SavedMeal``, snapshotting what was in it at save time.
///
/// `foodID` is a soft link, not a relationship — the food may since have been
/// deleted, in which case logging falls back to ``nutrientsSnapshot``. This
/// mirrors how `DiaryEntry` snapshots nutrition rather than reading it live
/// from `FoodItem`.
struct SavedMealItem: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    /// Position within the meal. See ``SavedMeal/orderedItems``.
    var order: Int

    /// Soft link to `FoodItem.id`. Nil for an item that was never backed by a
    /// catalogue food (not expected in v1, but kept optional for safety).
    var foodID: UUID?

    var foodName: String
    var brandName: String?

    var quantity: Double
    var servingLabel: String
    var servingGramWeight: Double

    /// Nutrition already scaled by `quantity` and the serving, exactly like
    /// `DiaryEntry.nutrients`. Used as-is when the food has been deleted, and
    /// kept even when it hasn't, so a renamed or re-edited food doesn't
    /// change what a previously-saved meal logs.
    var nutrientsSnapshot: Nutrients

    init(
        id: UUID = UUID(),
        order: Int,
        foodID: UUID? = nil,
        foodName: String,
        brandName: String? = nil,
        quantity: Double,
        servingLabel: String,
        servingGramWeight: Double,
        nutrientsSnapshot: Nutrients
    ) {
        self.id = id
        self.order = order
        self.foodID = foodID
        self.foodName = foodName
        self.brandName = brandName
        self.quantity = quantity
        self.servingLabel = servingLabel
        self.servingGramWeight = servingGramWeight
        self.nutrientsSnapshot = nutrientsSnapshot
    }
}
