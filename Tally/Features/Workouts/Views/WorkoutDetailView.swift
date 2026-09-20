import SwiftData
import SwiftUI

/// Read-only view of a finished session: every exercise and set as logged,
/// plus the workout-level summary (duration, volume, set count).
struct WorkoutDetailView: View {
    var workout: Workout

    @Environment(\.modelContext) private var modelContext
    @State private var didSaveRoutine = false

    var body: some View {
        List {
            Section {
                summary
            }
            ForEach(workout.orderedExercises) { entry in
                Section(entry.displayName) {
                    ForEach(entry.orderedSets) { set in
                        setRow(set)
                    }
                }
            }
        }
        .navigationTitle(workout.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Save as Routine", systemImage: "square.and.arrow.down", action: saveAsRoutine)
            }
        }
        .alert("Routine Saved", isPresented: $didSaveRoutine) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("\"\(workout.name)\" was added to your routines.")
        }
    }

    private var weightUnit: WeightUnit { UserSettings.current(in: modelContext).weightUnit }

    private var summary: some View {
        HStack {
            summaryColumn(value: Format.duration(workout.duration), label: "Duration")
            Spacer()
            summaryColumn(value: Format.weight(workout.totalVolumeKG, in: weightUnit), label: "Volume")
            Spacer()
            summaryColumn(value: "\(workout.completedSetCount)", label: "Sets")
        }
    }

    private func summaryColumn(value: String, label: String) -> some View {
        VStack(spacing: Theme.Spacing.xxs) {
            Text(value).font(Theme.Typography.metricSmall)
            Text(label).font(Theme.Typography.caption).foregroundStyle(Theme.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }

    private func setRow(_ set: SetEntry) -> some View {
        HStack {
            Text(set.isDropSet ? "Drop" : "Set")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
                .frame(width: 44, alignment: .leading)
            Text(Format.weight(set.weightKG, in: weightUnit))
                .font(Theme.Typography.setValue)
            Text("×")
                .foregroundStyle(Theme.Colors.tertiaryText)
            Text("\(set.reps)")
                .font(Theme.Typography.setValue)
            if set.isWarmup {
                Text("Warm-up")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.warning)
            }
            Spacer()
        }
        .opacity(set.isCompleted ? 1 : 0.4)
    }

    private func saveAsRoutine() {
        let routine = RoutineConversion.makeRoutine(from: workout)
        modelContext.insert(routine)
        try? modelContext.save()
        didSaveRoutine = true
    }
}

#Preview {
    let container = TallySchema.previewContainer()
    let workout = WorkoutsPreviewData.makeFinishedWorkout(in: container.mainContext)

    return NavigationStack {
        WorkoutDetailView(workout: workout)
    }
    .modelContainer(container)
    .environment(\.appEnvironment, .preview())
}
