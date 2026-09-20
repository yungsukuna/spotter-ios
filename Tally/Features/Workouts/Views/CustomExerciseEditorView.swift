import SwiftData
import SwiftUI

/// Create (or, given an existing exercise, edit) a custom exercise.
///
/// Built-in exercises cannot be edited here — only archived, from
/// `ExerciseLibraryManagementView` — since changing a seeded exercise's
/// muscle group out from under existing history would be surprising.
struct CustomExerciseEditorView: View {
    var existingExercise: Exercise?
    var onSave: (Exercise) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var muscleGroup: MuscleGroup
    @State private var equipment: Equipment
    @State private var isCardio: Bool

    init(existingExercise: Exercise? = nil, onSave: @escaping (Exercise) -> Void) {
        self.existingExercise = existingExercise
        self.onSave = onSave
        _name = State(initialValue: existingExercise?.name ?? "")
        _muscleGroup = State(initialValue: existingExercise?.muscleGroup ?? .fullBody)
        _equipment = State(initialValue: existingExercise?.equipment ?? .other)
        _isCardio = State(initialValue: existingExercise?.isCardio ?? false)
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
            }
            Section {
                Picker("Muscle Group", selection: $muscleGroup) {
                    ForEach(MuscleGroup.allCases) { group in
                        Text(group.displayName).tag(group)
                    }
                }
                Picker("Equipment", selection: $equipment) {
                    ForEach(Equipment.allCases) { eq in
                        Text(eq.displayName).tag(eq)
                    }
                }
                Toggle("Cardio Exercise", isOn: $isCardio)
            }
        }
        .navigationTitle(existingExercise == nil ? "New Exercise" : "Edit Exercise")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let exercise = existingExercise ?? Exercise(name: trimmedName, isCustom: true)
        exercise.name = trimmedName
        exercise.muscleGroup = muscleGroup
        exercise.equipment = equipment
        exercise.isCardio = isCardio

        if existingExercise == nil {
            modelContext.insert(exercise)
        }
        try? modelContext.save()
        onSave(exercise)
        dismiss()
    }
}

#Preview {
    NavigationStack {
        CustomExerciseEditorView { _ in }
    }
    .modelContainer(TallySchema.previewContainer())
    .environment(\.appEnvironment, .preview())
}
