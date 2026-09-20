import SwiftData
import SwiftUI

/// One set: a weight field, a rep field, and a completion button.
///
/// This row is the single most-tapped piece of UI in the whole app — tapped
/// repeatedly, mid-set, often with shaky hands — so every control here clears
/// `Theme.Layout.minimumTapTarget` and numbers use monospaced digits so the
/// row does not jitter as they change.
struct SetRowView: View {
    @Bindable var set: SetEntry
    /// "1", "2", … for working sets; drop sets show no number, just an
    /// indent, matching how RepCount renders them.
    var displayLabel: String
    var placeholder: PreviousPerformance.SetPlaceholder?
    var weightUnit: WeightUnit
    var isPersonalRecord: Bool
    var onComplete: () -> Void
    var onAddDropSet: () -> Void
    var onToggleWarmup: () -> Void
    var onDelete: () -> Void

    @State private var weightText: String = ""
    @State private var repsText: String = ""

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(set.isDropSet ? "↳" : displayLabel)
                .font(Theme.Typography.setValue)
                .foregroundStyle(Theme.Colors.secondaryText)
                .frame(minWidth: 24)

            TextField(weightPlaceholderText, text: $weightText)
                .keyboardType(.decimalPad)
                .font(Theme.Typography.setValue)
                .multilineTextAlignment(.center)
                .frame(minWidth: 56, minHeight: Theme.Layout.minimumTapTarget)

            Text("×")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.tertiaryText)

            TextField(repsPlaceholderText, text: $repsText)
                .keyboardType(.numberPad)
                .font(Theme.Typography.setValue)
                .multilineTextAlignment(.center)
                .frame(minWidth: 40, minHeight: Theme.Layout.minimumTapTarget)

            if set.isWarmup {
                Text("W")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.warning)
            }

            if isPersonalRecord {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(Theme.Colors.personalRecord)
            }

            Spacer(minLength: 0)

            Button(action: complete) {
                Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(set.isCompleted ? Theme.Colors.success : Theme.Colors.secondaryText)
            }
            .frame(minWidth: Theme.Layout.minimumTapTarget, minHeight: Theme.Layout.minimumTapTarget)
        }
        .padding(.leading, set.isDropSet ? Theme.Spacing.xl : 0)
        .padding(.vertical, Theme.Spacing.xs)
        .padding(.horizontal, Theme.Spacing.sm)
        .background(set.isCompleted ? Theme.Colors.setRowCompleted : Theme.Colors.setRowPending)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
        .contextMenu {
            Button("Add Drop Set", systemImage: "arrow.turn.down.right", action: onAddDropSet)
            Button(set.isWarmup ? "Unmark Warm-up" : "Mark as Warm-up", systemImage: "flame", action: onToggleWarmup)
            Button("Delete Set", systemImage: "trash", role: .destructive, action: onDelete)
        }
        .onAppear(perform: seedTextIfNeeded)
    }

    private var weightPlaceholderText: String {
        guard let kg = placeholder?.weightKG, kg > 0 else { return "0" }
        return Format.weight(kg, in: weightUnit, includeUnit: false)
    }

    private var repsPlaceholderText: String {
        guard let reps = placeholder?.reps, reps > 0 else { return "0" }
        return "\(reps)"
    }

    /// Seed the fields from an already-logged value — e.g. reopening a
    /// session after relaunch — rather than the previous session's
    /// placeholder, which would be wrong once this set has its own numbers.
    private func seedTextIfNeeded() {
        guard weightText.isEmpty, repsText.isEmpty else { return }
        if set.weightKG > 0 {
            weightText = Format.weight(set.weightKG, in: weightUnit, includeUnit: false)
        }
        if set.reps > 0 {
            repsText = "\(set.reps)"
        }
    }

    private func complete() {
        if set.isCompleted {
            set.uncomplete()
            return
        }
        set.weightKG = SetInputResolver.resolveWeightKG(
            text: weightText,
            unit: weightUnit,
            placeholderKG: placeholder?.weightKG
        )
        set.reps = SetInputResolver.resolveReps(text: repsText, placeholderReps: placeholder?.reps)
        set.complete()
        onComplete()
    }
}

#Preview {
    let container = TallySchema.previewContainer()
    let exercise = Exercise(name: "Bench Press", equipment: .barbell, muscleGroup: .chest)
    container.mainContext.insert(exercise)
    let workout = Workout()
    container.mainContext.insert(workout)
    let entry = workout.addExercise(exercise)
    let set = entry.addSet(weightKG: 60, reps: 8)

    return VStack(spacing: Theme.Spacing.sm) {
        SetRowView(
            set: set,
            displayLabel: "1",
            placeholder: .init(weightKG: 60, reps: 8, isWarmup: false, isDropSet: false),
            weightUnit: .kilograms,
            isPersonalRecord: false,
            onComplete: {},
            onAddDropSet: {},
            onToggleWarmup: {},
            onDelete: {}
        )
    }
    .padding()
    .modelContainer(container)
    .environment(\.appEnvironment, .preview())
}
