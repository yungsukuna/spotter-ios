import SwiftData
import SwiftUI

/// Manage the exercise library: create or edit custom exercises, and archive
/// built-ins that will never get used.
///
/// Built-in exercises cannot be deleted — see the note on
/// `Exercise.isArchived` — only hidden from the picker.
struct ExerciseLibraryManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var showingNewExercise = false
    @State private var editingExercise: Exercise?

    var body: some View {
        List {
            ForEach(exercises) { exercise in
                HStack {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text(exercise.name)
                            .strikethrough(exercise.isArchived)
                            .foregroundStyle(exercise.isArchived ? Theme.Colors.secondaryText : Theme.Colors.primaryText)
                        Text(exercise.isCustom ? "Custom · \(exercise.muscleGroup.displayName)" : exercise.muscleGroup.displayName)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if exercise.isCustom { editingExercise = exercise }
                }
                .swipeActions(edge: .trailing) {
                    Button(exercise.isArchived ? "Unarchive" : "Archive") {
                        exercise.isArchived.toggle()
                    }
                    .tint(Theme.Colors.warning)

                    if exercise.isCustom {
                        Button("Delete", role: .destructive) {
                            modelContext.delete(exercise)
                        }
                    }
                }
            }
        }
        .navigationTitle("Exercise Library")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New", systemImage: "plus") { showingNewExercise = true }
            }
        }
        .sheet(isPresented: $showingNewExercise) {
            NavigationStack {
                CustomExerciseEditorView { _ in }
            }
        }
        .sheet(item: $editingExercise) { exercise in
            NavigationStack {
                CustomExerciseEditorView(existingExercise: exercise) { _ in }
            }
        }
    }
}

#Preview {
    NavigationStack {
        ExerciseLibraryManagementView()
    }
    .modelContainer(SpotterSchema.previewContainer())
    .environment(\.appEnvironment, .preview())
}
