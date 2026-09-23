import Foundation

/// Resolves what a set row's text fields actually mean, in storage units.
///
/// An empty field falls back to the previous session's placeholder value —
/// that fallback is what lets confirming an unchanged set be a single tap
/// instead of retyping numbers that did not change. A non-empty field is
/// parsed as a number in the user's display unit and converted to kilograms,
/// since everything is stored metric (see `UnitConverter`).
enum SetInputResolver {

    /// - Parameters:
    ///   - text: raw text field contents, in `unit`.
    ///   - unit: the display unit the text was typed in.
    ///   - placeholderKG: the previous session's weight for this set, already
    ///     in kilograms, or nil if there is no previous session.
    static func resolveWeightKG(text: String, unit: WeightUnit, placeholderKG: Double?) -> Double {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let typed = Double(trimmed), typed.isFinite else {
            return placeholderKG ?? 0
        }
        return UnitConverter.weightToKilograms(typed, from: unit)
    }

    /// Reps have no unit to convert, but the same empty-falls-back-to-placeholder
    /// rule applies.
    static func resolveReps(text: String, placeholderReps: Int?) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let typed = Int(trimmed) else {
            return placeholderReps ?? 0
        }
        return typed
    }
}
