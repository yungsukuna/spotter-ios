import Foundation

/// Pure logic behind quick-add diary entries: parsing the sheet's text fields
/// into a nutrition panel, building the entry itself, and detecting one after
/// the fact.
///
/// A quick-add entry gets no new stored field. It is a ``DiaryEntry`` with no
/// ``FoodItem`` link and a zero-gram serving — no real food ever has a
/// zero-weight serving, so that combination is a safe, unambiguous marker.
/// See ``DiaryEntry/isQuickAdd`` below.
enum QuickAdd {
    /// The serving label stamped on every quick-add entry.
    static let servingLabel = "Quick add"

    /// The fallback name when the user leaves the name field blank.
    static let defaultName = "Quick add"

    /// Parses a number field, accepting either `.` or `,` as the decimal
    /// separator so a localized keyboard doesn't get rejected. Blank or
    /// unparsable text is `nil`.
    static func parseDouble(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }

    /// Builds the nutrition panel from the sheet's text fields.
    ///
    /// `nil` when calories is missing or unparsable — kcal is the one
    /// required field, since a quick-add entry with no calories at all isn't
    /// worth logging. Blank macro fields become `nil` (unknown), never `0` —
    /// a typed `"0"` is kept as a real zero.
    static func makeNutrients(
        kcalText: String,
        proteinText: String = "",
        carbsText: String = "",
        fatText: String = ""
    ) -> Nutrients? {
        guard let kcal = parseDouble(kcalText) else { return nil }
        return Nutrients(
            kcal: kcal,
            proteinG: parseDouble(proteinText),
            carbsG: parseDouble(carbsText),
            fatG: parseDouble(fatText)
        )
    }

    /// Builds the diary entry once the nutrition panel is known.
    static func makeEntry(
        name: String,
        nutrients: Nutrients,
        meal: Meal,
        at date: Date = Date(),
        calendar: Calendar = .current
    ) -> DiaryEntry {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return DiaryEntry(
            loggedAt: date,
            meal: meal,
            foodName: trimmedName.isEmpty ? defaultName : trimmedName,
            quantity: 1,
            serving: ServingSize(label: servingLabel, gramWeight: 0),
            nutrients: nutrients,
            calendar: calendar
        )
    }
}

extension DiaryEntry {
    /// True for an entry logged through quick add rather than a catalogue
    /// food. No real serving ever weighs zero grams, so a nil food link plus
    /// a zero-gram serving is an unambiguous marker — see the type-level note
    /// on ``QuickAdd`` for why this needs no new stored field. An entry whose
    /// food was later deleted also has a nil food link, but keeps its real
    /// (non-zero) `servingGramWeight`, so it is correctly *not* quick-add.
    var isQuickAdd: Bool {
        food == nil && servingGramWeight == 0
    }
}
