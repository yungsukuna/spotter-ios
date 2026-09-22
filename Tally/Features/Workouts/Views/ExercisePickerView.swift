import SwiftData
import SwiftUI

/// Searchable, filterable exercise picker, grouped by muscle region. Used
/// both to add an exercise to the active session and, via `RoutineEditorView`,
/// to build a routine.
struct ExercisePickerView: View {
    /// Which slice of the library this picker shows. `.strength` (the
    /// default) excludes cardio exercises — this is the fix for the bug
    /// where adding "Running" to a workout used to offer weight×reps rows.
    /// `.cardioOnly` is used by `CardioEntrySheet`.
    enum Mode {
        case strength
        case cardioOnly
    }

    var mode: Mode = .strength
    var onSelect: (Exercise) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.name) private var allExercises: [Exercise]

    @State private var query = ""
    @State private var muscleGroup: MuscleGroup?
    @State private var equipment: Equipment?
    @State private var showingCustomExercise = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(sections) { section in
                    Section(section.region) {
                        ForEach(section.exercises) { exercise in
                            Button {
                                onSelect(exercise)
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                                        Text(exercise.name)
                                            .foregroundStyle(Theme.Colors.primaryText)
                                        Text(exercise.equipment.displayName)
                                            .font(Theme.Typography.caption)
                                            .foregroundStyle(Theme.Colors.secondaryText)
                                    }
                                    Spacer()
                                }
                                .frame(minHeight: Theme.Layout.minimumTapTarget)
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search exercises")
            .navigationTitle(mode == .cardioOnly ? "Choose Cardio Exercise" : "Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Create Custom Exercise", systemImage: "plus") {
                            showingCustomExercise = true
                        }
                        if mode == .strength {
                            Divider()
                            filterMenuContent
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .sheet(isPresented: $showingCustomExercise) {
                NavigationStack {
                    CustomExerciseEditorView { exercise in
                        onSelect(exercise)
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var filterMenuContent: some View {
        Picker("Muscle Group", selection: $muscleGroup) {
            Text("All Muscle Groups").tag(MuscleGroup?.none)
            ForEach(MuscleGroup.allCases) { group in
                Text(group.displayName).tag(MuscleGroup?.some(group))
            }
        }
        Picker("Equipment", selection: $equipment) {
            Text("All Equipment").tag(Equipment?.none)
            ForEach(Equipment.allCases) { eq in
                Text(eq.displayName).tag(Equipment?.some(eq))
            }
        }
    }

    private var sections: [ExercisePickerFilter.RegionSection] {
        let filtered = ExercisePickerFilter.filtered(
            allExercises,
            query: query,
            muscleGroup: mode == .cardioOnly ? nil : muscleGroup,
            equipment: mode == .cardioOnly ? nil : equipment,
            includeCardio: mode == .cardioOnly
        )
        let scoped = mode == .cardioOnly ? filtered.filter(\.isCardio) : filtered
        return ExercisePickerFilter.groupedByRegion(scoped)
    }
}

#Preview {
    ExercisePickerView { _ in }
        .modelContainer(TallySchema.previewContainer())
        .environment(\.appEnvironment, .preview())
}

#Preview("Cardio Only") {
    ExercisePickerView(mode: .cardioOnly) { _ in }
        .modelContainer(TallySchema.previewContainer())
        .environment(\.appEnvironment, .preview())
}
