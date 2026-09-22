import Foundation

/// Search and grouping logic for the exercise picker, kept free of SwiftUI so
/// it can be tested against plain arrays of `Exercise`.
enum ExercisePickerFilter {

    /// One section of the grouped picker list.
    ///
    /// A named type rather than a tuple: Swift key paths cannot refer to
    /// tuple elements by label, which both `ForEach` and callers comparing
    /// results in tests would otherwise need.
    struct RegionSection: Identifiable, Hashable {
        var region: String
        var exercises: [Exercise]
        var id: String { region }
    }

    /// Whether `exercise` should show up under the current query and filters.
    ///
    /// `includeCardio` defaults to `false` so every existing caller — the
    /// strength picker, `RoutineEditorView` — keeps excluding cardio
    /// exercises without having to opt in. `CardioEntrySheet`'s picker passes
    /// `true` (and then narrows further to cardio-only itself; this flag only
    /// controls whether cardio is *excluded*, not whether it's the only thing
    /// shown).
    static func matches(
        _ exercise: Exercise,
        query: String,
        muscleGroup: MuscleGroup?,
        equipment: Equipment?,
        includeArchived: Bool = false,
        includeCardio: Bool = false
    ) -> Bool {
        if !includeArchived && exercise.isArchived { return false }
        if !includeCardio && exercise.isCardio { return false }
        if let muscleGroup, exercise.muscleGroup != muscleGroup { return false }
        if let equipment, exercise.equipment != equipment { return false }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return exercise.name.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    static func filtered(
        _ exercises: [Exercise],
        query: String,
        muscleGroup: MuscleGroup? = nil,
        equipment: Equipment? = nil,
        includeArchived: Bool = false,
        includeCardio: Bool = false
    ) -> [Exercise] {
        exercises.filter {
            matches(
                $0,
                query: query,
                muscleGroup: muscleGroup,
                equipment: equipment,
                includeArchived: includeArchived,
                includeCardio: includeCardio
            )
        }
    }

    /// Exercises grouped by `MuscleGroup.region` for the picker's section
    /// headers, sections and exercises both sorted by name so the list is
    /// stable between launches.
    static func groupedByRegion(_ exercises: [Exercise]) -> [RegionSection] {
        let grouped = Dictionary(grouping: exercises) { $0.muscleGroup.region }
        return grouped
            .map { RegionSection(region: $0.key, exercises: $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.region < $1.region }
    }
}
