import Foundation

/// Portion helpers mirroring ``FoodItem``'s, so the detail/portion picker can
/// present a not-yet-saved search result exactly the way it presents an
/// already-saved food, before any ``FoodItem`` exists for it.
extension FoodRecord {
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
}
