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
    var setEffortDisplay: SetEffortDisplay
    /// `UserSettings.barbellWeightKG`. Nil means the plate calculator and the
    /// warm-up generator fall back to `PlateCalculator.defaultBarWeightKG`.
    var barbellWeightKG: Double?
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
    var onSetCompleted: (WorkoutExercise) -> Void

    private enum NoteScope: String, CaseIterable, Hashable {
        case exercise = "Exercise Note"
        case session = "Today Only"
    }

    @State private var isEditingNote = false
    @State private var noteScope: NoteScope = .exercise
    @State private var noteDraft = ""
    @State private var plateCalculatorSet: SetEntry?

    private var isBarbell: Bool { entry.exercise?.equipment == .barbell }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            header
            if isEditingNote {
                noteEditor
            }
            ForEach(entry.orderedSets) { set in
                SetRowView(
                    set: set,
                    displayLabel: workingSetLabel(for: set),
                    placeholder: placeholder(for: set),
                    weightUnit: weightUnit,
                    setEffortDisplay: setEffortDisplay,
                    isBarbell: isBarbell,
                    isPersonalRecord: isPersonalRecord(set),
                    onComplete: { onSetCompleted(entry) },
                    onAddDropSet: { DropSetInsertion.insertDropSet(after: set) },
                    onToggleWarmup: { set.isWarmup.toggle() },
                    onShowPlateCalculator: { plateCalculatorSet = set },
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
        .sheet(item: $plateCalculatorSet) { set in
            PlateCalculatorSheet(targetKG: set.weightKG, weightUnit: weightUnit)
        }
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
                if let exerciseNote = entry.exercise?.notes, !exerciseNote.isEmpty {
                    Label(exerciseNote, systemImage: "pin.fill")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
                if let sessionNote = entry.notes, !sessionNote.isEmpty {
                    Label(sessionNote, systemImage: "text.bubble")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
            }
            Spacer()
            Menu {
                Button("History", systemImage: "clock.arrow.circlepath", action: onShowHistory)
                Button("Stats", systemImage: "chart.xyaxis.line", action: onShowStats)
                Button("Edit Note", systemImage: "note.text", action: beginEditingNote)
                Menu("Rest Timer") {
                    restTimerMenuContent
                }
                Button("Add Warm-up Sets", systemImage: "flame", action: addWarmups)
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

    /// "Default (1:30)" / "0:30" / … / "5:00" / "Off", writing back to the
    /// exercise's own override — nil restores the global default.
    @ViewBuilder
    private var restTimerMenuContent: some View {
        Button("Default", action: { setRestOverride(nil) })
        ForEach([30, 60, 90, 120, 150, 180, 240, 300], id: \.self) { seconds in
            Button(Format.duration(TimeInterval(seconds)), action: { setRestOverride(seconds) })
        }
        Button("Off", action: { setRestOverride(0) })
    }

    private func setRestOverride(_ seconds: Int?) {
        entry.exercise?.restTimerSeconds = seconds
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

    /// The previous session's numbers for the set of the same *kind* as
    /// `set` (see `PreviousPerformance.SetKind`), or nil if there is no
    /// previous session or it had no set of that kind.
    private func placeholder(for set: SetEntry) -> PreviousPerformance.SetPlaceholder? {
        guard let exercise = entry.exercise else { return nil }
        let ordered = entry.orderedSets
        guard let index = ordered.firstIndex(where: { $0.id == set.id }) else { return nil }
        return PreviousPerformance.placeholder(atIndex: index, in: ordered, for: exercise, excludingWorkout: workout)
    }

    private func isPersonalRecord(_ set: SetEntry) -> Bool {
        guard let candidate = set.completedSetValue else { return false }
        return StrengthMath.isPersonalRecord(candidate: candidate, against: priorCompletedSets)
    }

    // MARK: - Notes

    private func beginEditingNote() {
        if let sessionNote = entry.notes, !sessionNote.isEmpty {
            noteScope = .session
            noteDraft = sessionNote
        } else {
            noteScope = .exercise
            noteDraft = entry.exercise?.notes ?? ""
        }
        isEditingNote = true
    }

    private var noteEditor: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Picker("Note type", selection: $noteScope) {
                ForEach(NoteScope.allCases, id: \.self) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            TextField("Note", text: $noteDraft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Done", action: saveNote)
                    .frame(minHeight: Theme.Layout.minimumTapTarget)
            }
        }
    }

    private func saveNote() {
        let trimmed = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        switch noteScope {
        case .exercise:
            entry.exercise?.notes = trimmed.isEmpty ? nil : trimmed
        case .session:
            entry.notes = trimmed.isEmpty ? nil : trimmed
        }
        isEditingNote = false
    }

    // MARK: - Warm-ups

    private func addWarmups() {
        guard let exercise = entry.exercise else { return }
        let ordered = entry.orderedSets
        guard let firstWorkingIndex = ordered.firstIndex(where: { !$0.isWarmup && !$0.isDropSet }) else { return }

        var placeholderWeightKG: Double?
        if ordered[firstWorkingIndex].weightKG <= 0 {
            placeholderWeightKG = PreviousPerformance.placeholder(
                atIndex: firstWorkingIndex,
                in: ordered,
                for: exercise,
                excludingWorkout: workout
            )?.weightKG
        }

        let bar = barbellWeightKG ?? PlateCalculator.defaultBarWeightKG(for: weightUnit)
        WarmupGenerator.insertWarmups(
            into: entry,
            barKG: bar,
            unit: weightUnit,
            placeholderWeightKG: placeholderWeightKG
        )
    }
}

#Preview {
    let container = TallySchema.previewContainer()
    let workout = WorkoutsPreviewData.makeInProgressWorkout(in: container.mainContext)
    let entry = workout.orderedExercises.first!

    return ExerciseLogCardView(
        entry: entry,
        workout: workout,
        weightUnit: .kilograms,
        setEffortDisplay: .rpe,
        barbellWeightKG: nil,
        bracketPosition: .none,
        canGroupWithNext: false,
        priorCompletedSets: [],
        onShowHistory: {},
        onShowStats: {},
        onGroupWithNext: {},
        onUngroup: {},
        onRemove: {},
        onSetCompleted: { _ in }
    )
    .padding()
    .modelContainer(container)
    .environment(\.appEnvironment, .preview())
}
