import Foundation
import SwiftData

/// One logged portion of food on one day.
///
/// The nutrition figures here are a **snapshot**, not a live reference to the
/// food. That is the important design decision in this type. Open Food Facts is
/// crowd-edited and USDA records get revised; if a product's calorie count is
/// corrected upstream next month, that must not silently rewrite what last
/// month's diary says the user ate. Same reasoning for the food's name and
/// brand, which are copied here so history still reads correctly after the food
/// is edited or deleted.
///
/// ``food`` is kept as a nullify-on-delete convenience link for "log this
/// again", and is allowed to be nil.
@Model
final class DiaryEntry {
    var id: UUID = UUID()

    /// Exact time of logging — used for ordering within a meal.
    var loggedAt: Date = Date()

    /// `yyyy-MM-dd` in the user's calendar, produced by `DayKey.make(from:)`.
    ///
    /// Day-bucketed queries are the most common read in this app, and a string
    /// equality predicate is both faster and far less error-prone than date
    /// range arithmetic across DST boundaries.
    var dayKey: String = ""

    /// Raw value of ``Meal`` — see the note in `Enums.swift`.
    var mealRaw: String = Meal.snack.rawValue

    // MARK: - Snapshot of what was eaten

    var foodName: String = ""
    var brandName: String?
    /// How many of ``servingLabel`` were eaten, e.g. 1.5.
    var quantity: Double = 1
    var servingLabel: String = "100 g"
    var servingGramWeight: Double = 100
    /// Nutrition actually consumed — already scaled by quantity and serving.
    var nutrients: Nutrients = Nutrients.empty

    /// Optional link back to the source food. Nil if that food was deleted.
    var food: FoodItem?

    init(
        id: UUID = UUID(),
        loggedAt: Date = Date(),
        meal: Meal,
        foodName: String,
        brandName: String? = nil,
        quantity: Double,
        serving: ServingSize,
        nutrients: Nutrients,
        food: FoodItem? = nil,
        calendar: Calendar = .current
    ) {
        self.id = id
        self.loggedAt = loggedAt
        self.dayKey = DayKey.make(from: loggedAt, calendar: calendar)
        self.mealRaw = meal.rawValue
        self.foodName = foodName
        self.brandName = brandName
        self.quantity = quantity
        self.servingLabel = serving.label
        self.servingGramWeight = serving.gramWeight
        self.nutrients = nutrients
        self.food = food
    }

    /// Build an entry from a food, computing the snapshot in one place so no
    /// caller has to remember to scale the nutrition itself.
    convenience init(
        logging food: FoodItem,
        quantity: Double,
        serving: ServingSize,
        meal: Meal,
        at date: Date = Date(),
        calendar: Calendar = .current
    ) {
        self.init(
            loggedAt: date,
            meal: meal,
            foodName: food.name,
            brandName: food.brand,
            quantity: quantity,
            serving: serving,
            nutrients: food.nutrients(quantity: quantity, serving: serving),
            food: food,
            calendar: calendar
        )
    }

    var meal: Meal {
        get { Meal(rawValue: mealRaw) ?? .snack }
        set { mealRaw = newValue.rawValue }
    }

    /// Total grams consumed.
    var totalGrams: Double { servingGramWeight * quantity }

    /// "1.5 × 1 slice", or just "1 slice" when the quantity is exactly one.
    var portionDescription: String {
        if abs(quantity - 1) < 0.001 { return servingLabel }
        return "\(QuantityFormatter.string(from: quantity)) × \(servingLabel)"
    }

    /// Keep ``dayKey`` consistent after the timestamp is edited.
    func updateLoggedAt(_ date: Date, calendar: Calendar = .current) {
        loggedAt = date
        dayKey = DayKey.make(from: date, calendar: calendar)
    }
}
