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
        parseWeightKG(text: text, unit: unit) ?? placeholderKG ?? 0
    }

    /// Reps have no unit to convert, but the same empty-falls-back-to-placeholder
    /// rule applies.
    static func resolveReps(text: String, placeholderReps: Int?) -> Int {
        parseReps(text: text) ?? placeholderReps ?? 0
    }

    /// The typed weight in kilograms, or nil when the field is empty or not a
    /// number. Accepts a comma decimal separator, which is what the decimal
    /// pad produces in locales like de_DE.
    static func parseWeightKG(text: String, unit: WeightUnit) -> Double? {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty, let typed = Double(normalized), typed.isFinite, typed >= 0 else {
            return nil
        }
        return UnitConverter.weightToKilograms(typed, from: unit)
    }

    /// The typed rep count, or nil when the field is empty or not a whole
    /// number.
    static func parseReps(text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let typed = Int(trimmed), typed >= 0 else { return nil }
        return typed
    }

    /// The kilograms to write back to the set as the user types, or nil when
    /// the stored value should be left alone.
    ///
    /// Leaves it alone when the text is unparsable, and when the stored value
    /// already *displays* as what was typed. The second case matters in
    /// pounds: a set stored as 60 kg shows as "132.3", and converting that
    /// text back would store 60.01 kg — enough drift to award a false PR.
    static func weightKGToStore(text: String, unit: WeightUnit, currentKG: Double) -> Double? {
        guard let typedKG = parseWeightKG(text: text, unit: unit) else { return nil }
        let typedDisplay = (UnitConverter.weight(typedKG, in: unit) * 10).rounded()
        let currentDisplay = (UnitConverter.weight(currentKG, in: unit) * 10).rounded()
        return typedDisplay == currentDisplay ? nil : typedKG
    }

    /// A set needs at least one rep to count as performed. Weight may be zero
    /// — that is bodyweight work — but a zero-rep set is an empty row.
    static func canComplete(reps: Int) -> Bool {
        reps > 0
    }
}
