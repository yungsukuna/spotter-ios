import SwiftData
import SwiftUI

/// One exercise's block on the logging screen: a header plus every set row,
/// inline. There is no drill-down — this card *is* the whole interaction
/// surface for the exercise, which is the defining trait of the RepCount
/// logging screen.
struct ExerciseLogCardView: View {
    @Bindable var entry: WorkoutExercise
    var workout: Workout
    var weightUnit: WeightUnit
    var bracketPosition: SupersetGrouping.BracketPosition
    var canGroupWithNext: Bool
    /// Completed sets for this exercise from every *other* workout, used for
    /// the PR badge. Excludes the current session so a set is never compared
    /// against itself.
    var priorCompletedSets: [StrengthMath.CompletedSet]
    var onShowHistory: () -> Void
    var onShowStats: () -> Void
    var onGroupWithNext: () -> Void
    var onUngroup: () -> Void
    var onRemove: () -> Void
    var onSetCompleted: () -> Void

    private var placeholders: [PreviousPerformance.SetPlaceholder] {
        guard let exercise = entry.exercise else { return [] }
        return PreviousPerformance.placeholders(for: exercise, excludingWorkout: workout)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            header
            ForEach(entry.orderedSets) { set in
                SetRowView(
                    set: set,
                    displayLabel: workingSetLabel(for: set),
                    placeholder: placeholder(for: set),
                    weightUnit: weightUnit,
                    isPersonalRecord: isPersonalRecord(set),
                    onComplete: onSetCompleted,
                    onAddDropSet: { DropSetInsertion.insertDropSet(after: set) },
                    onToggleWarmup: { set.isWarmup.toggle() },
                    onDelete: { entry.removeSet(set) }
                )
            }
            Button {
                entry.addSet()
            } label: {
                Label("Add Set", systemImage: "plus")
                    .font(Theme.Typography.caption)
            }
            .padding(.top, Theme.Spacing.xxs)
        }
        .padding(Theme.Layout.cardPadding)
        .background(Theme.Colors.cardBackground)
        .clipShape(cardShape)
        .overlay(alignment: .leading) { supersetBracket }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(entry.displayName)
                    .font(Theme.Typography.cardTitle)
                if let best = entry.bestEstimatedOneRepMax() {
                    Text("Est. 1RM \(Format.weight(best, in: weightUnit))")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
            }
            Spacer()
            Menu {
                Button("History", systemImage: "clock.arrow.circlepath", action: onShowHistory)
                Button("Stats", systemImage: "chart.xyaxis.line", action: onShowStats)
                if entry.isInSuperset {
                    Button("Ungroup Superset", systemImage: "link.badge.minus", action: onUngroup)
                } else if canGroupWithNext {
                    Button("Group with Next Exercise", systemImage: "link", action: onGroupWithNext)
                }
                Button("Remove Exercise", systemImage: "trash", role: .destructive, action: onRemove)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .frame(minWidth: Theme.Layout.minimumTapTarget, minHeight: Theme.Layout.minimumTapTarget)
            }
        }
    }

    /// The bracket down the leading edge of a superset. Corner rounding
    /// matches the card's own position within the run so consecutive cards
    /// read as one continuous group rather than separate rounded boxes.
    @ViewBuilder
    private var supersetBracket: some View {
        if bracketPosition != .none {
            RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                .fill(Theme.Colors.workout)
                .frame(width: 4)
                .padding(.vertical, bracketPosition == .middle ? 0 : Theme.Spacing.sm)
        }
    }

    private var cardShape: some Shape {
        RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
    }

    /// "1", "2", … counting only working sets — drop sets ride along under
    /// their parent and are never numbered.
    private func workingSetLabel(for set: SetEntry) -> String {
        guard !set.isDropSet else { return "" }
        let ordered = entry.orderedSets
        guard let index = ordered.firstIndex(where: { $0.id == set.id }) else { return "" }
        let count = ordered[0...index].filter { !$0.isDropSet }.count
        return "\(count)"
    }

    /// The previous session's numbers for the set at the same position as
    /// `set`, or nil if there is no previous session or it had fewer sets.
    private func placeholder(for set: SetEntry) -> PreviousPerformance.SetPlaceholder? {
        let ordered = entry.orderedSets
        guard let index = ordered.firstIndex(where: { $0.id == set.id }), index < placeholders.count else {
            return nil
        }
        return placeholders[index]
    }

    private func isPersonalRecord(_ set: SetEntry) -> Bool {
        guard let candidate = set.completedSetValue else { return false }
        return StrengthMath.isPersonalRecord(candidate: candidate, against: priorCompletedSets)
    }
}
