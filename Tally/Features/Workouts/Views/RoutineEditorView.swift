import SwiftData
import SwiftUI

/// Create or edit a routine's structure: name, exercises, target set counts,
/// order. Weights are never edited here — see the note on `Routine` for why.
///
/// Used both pushed from `RoutineListView` (editing an existing routine, in
/// the app's own `NavigationStack`) and presented as a sheet for "New
/// Routine" — the caller wraps it in its own `NavigationStack` in that case.
struct RoutineEditorView: View {
    @Bindable var routine: Routine
    private let isNew: Bool

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showingExercisePicker = false

    init(routine: Routine?) {
        if let routine {
            self.isNew = false
            _routine = Bindable(wrappedValue: routine)
        } else {
            self.isNew = true
            _routine = Bindable(wrappedValue: Routine(name: "New Routine"))
        }
    }

    var body: some View {
        Form {
            Section {
                TextField("Routine Name", text: $routine.name)
            }
            Section("Exercises") {
                if routine.exerciseCount == 0 {
                    Text("No exercises yet.")
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
                ForEach(routine.orderedExercises) { entry in
                    HStack {
                        Text(entry.displayName)
                        Spacer()
                        Stepper(
                            "\(entry.targetSets) sets",
                            value: Binding(
                                get: { entry.targetSets },
                                set: { entry.targetSets = max(1, $0) }
                            ),
                            in: 1...20
                        )
                        .fixedSize()
                    }
                }
                .onDelete(perform: removeExercise)
                .onMove(perform: moveExercise)

                Button {
                    showingExercisePicker = true
                } label: {
                    Label("Add Exercise", systemImage: "plus")
                }
            }
        }
        .navigationTitle(isNew ? "New Routine" : "Edit Routine")
        .toolbar {
            if isNew {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(routine.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else {
                ToolbarItem(placement: .primaryAction) {
                    EditButton()
                }
            }
        }
        .sheet(isPresented: $showingExercisePicker) {
            ExercisePickerView { exercise in
                routine.addExercise(exercise)
                if !isNew {
                    try? modelContext.save()
                }
            }
        }
    }

    private func save() {
        if isNew {
            modelContext.insert(routine)
        }
        try? modelContext.save()
        dismiss()
    }

    private func removeExercise(at offsets: IndexSet) {
        let ordered = routine.orderedExercises
        for index in offsets {
            routine.removeExercise(ordered[index])
        }
        if !isNew {
            try? modelContext.save()
        }
    }

    private func moveExercise(from source: IndexSet, to destination: Int) {
        var ordered = routine.orderedExercises
        ordered.move(fromOffsets: source, toOffset: destination)
        routine.reorderExercises(to: ordered)
        if !isNew {
            try? modelContext.save()
        }
    }
}

#Preview {
    let container = TallySchema.previewContainer()
    let routine = WorkoutsPreviewData.seedRoutine(in: container.mainContext)

    return NavigationStack {
        RoutineEditorView(routine: routine)
    }
    .modelContainer(container)
    .environment(\.appEnvironment, .preview())
}
