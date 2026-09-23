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
    /// Whether — and how — to show the effort menu. `.off` hides it entirely,
    /// keeping the row as uncluttered as RepCount's by default.
    var setEffortDisplay: SetEffortDisplay
    /// Whether this set's exercise is a barbell lift, which is what gates the
    /// "Plate Calculator" context menu item.
    var isBarbell: Bool
    var isPersonalRecord: Bool
    var onComplete: () -> Void
    var onAddDropSet: () -> Void
    var onToggleWarmup: () -> Void
    var onShowPlateCalculator: () -> Void
    var onDelete: () -> Void

    @State private var weightText: String = ""
    @State private var repsText: String = ""
    @State private var rejectedCompletions = 0
    @FocusState private var isRepsFocused: Bool

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
                .focused($isRepsFocused)
                .font(Theme.Typography.setValue)
                .multilineTextAlignment(.center)
                .frame(minWidth: 40, minHeight: Theme.Layout.minimumTapTarget)

            if setEffortDisplay != .off {
                effortMenu
            }

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
            if isBarbell {
                Button("Plate Calculator", systemImage: "scalemass", action: onShowPlateCalculator)
            }
            Button("Delete Set", systemImage: "trash", role: .destructive, action: onDelete)
        }
        .onAppear(perform: seedTextIfNeeded)
        // Written through to the model on every keystroke, not just on
        // completion: the row's @State does not survive leaving the screen,
        // or a LazyVStack recycling the row, and a completed set that is
        // corrected must actually change.
        .onChange(of: weightText) { _, newValue in storeWeight(newValue) }
        .onChange(of: repsText) { _, newValue in storeReps(newValue) }
        .sensoryFeedback(.error, trigger: rejectedCompletions)
    }

    /// Compact menu between the reps field and the completion check: shows
    /// the current RPE/RIR (or just "RPE"/"RIR" when unset) and offers 6…10
    /// in half-point steps, plus Clear.
    private var effortMenu: some View {
        Menu {
            ForEach(SetEffort.selectableValues, id: \.self) { rpe in
                Button(SetEffort.formatted(rpe)) { set.rpe = rpe }
            }
            Divider()
            Button("Clear") { set.rpe = nil }
        } label: {
            Text(effortButtonText)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
        .frame(minHeight: Theme.Layout.minimumTapTarget)
    }

    private var effortButtonText: String {
        SetEffort.label(rpe: set.rpe, display: setEffortDisplay) ?? setEffortDisplay.displayName
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

    /// An emptied field on a pending set clears the stored value so the
    /// placeholder applies again on completion. On a completed set it leaves
    /// the logged value alone — clearing a field is not a way to log zero.
    private func storeWeight(_ text: String) {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if !set.isCompleted { set.weightKG = 0 }
            return
        }
        if let kg = SetInputResolver.weightKGToStore(text: text, unit: weightUnit, currentKG: set.weightKG) {
            set.weightKG = kg
        }
    }

    private func storeReps(_ text: String) {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if !set.isCompleted { set.reps = 0 }
            return
        }
        if let reps = SetInputResolver.parseReps(text: text), reps != set.reps {
            set.reps = reps
        }
    }

    private func complete() {
        if set.isCompleted {
            set.uncomplete()
            return
        }
        let weightKG = SetInputResolver.resolveWeightKG(
            text: weightText,
            unit: weightUnit,
            placeholderKG: placeholder?.weightKG
        )
        let reps = SetInputResolver.resolveReps(text: repsText, placeholderReps: placeholder?.reps)
        guard SetInputResolver.canComplete(reps: reps) else {
            rejectedCompletions += 1
            isRepsFocused = true
            return
        }
        set.weightKG = weightKG
        set.reps = reps
        // Show what was actually logged, rather than leaving the previous
        // session's numbers as grey placeholder text on a completed row.
        if weightKG > 0 {
            weightText = Format.weight(weightKG, in: weightUnit, includeUnit: false)
        }
        repsText = "\(reps)"
        set.complete()
        onComplete()
    }
}

#Preview {
    let container = SpotterSchema.previewContainer()
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
            setEffortDisplay: .rpe,
            isBarbell: true,
            isPersonalRecord: false,
            onComplete: {},
            onAddDropSet: {},
            onToggleWarmup: {},
            onShowPlateCalculator: {},
            onDelete: {}
        )
    }
    .padding()
    .modelContainer(container)
    .environment(\.appEnvironment, .preview())
}
