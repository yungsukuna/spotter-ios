import SwiftData
import SwiftUI

/// Log a single cardio session: exercise, duration, optional distance, an
/// estimated (or overridden) calorie figure, notes and date/time.
///
/// Deliberately separate from the strength set grid — see the note on
/// `CardioEntry` in `Exercise.swift`. `CardioEntry` has no relationship to a
/// `Workout`, so this sheet is used identically from `WorkoutsHomeView` (a
/// cardio session logged with no active workout) and from `ActiveWorkoutView`
/// (a treadmill finisher logged mid-session) — it never navigates to a
/// sub-screen, keeping the one-scrollable-screen rule intact for the session
/// it's presented over.
struct CardioEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var exercise: Exercise?
    @State private var showingExercisePicker = false
    @State private var minutesText = ""
    @State private var secondsText = ""
    @State private var distanceText = ""
    @State private var caloriesText = ""
    @State private var noCalorieEstimate = false
    @State private var notes = ""
    @State private var date = Date()
    @State private var settings: UserSettings?
    @FocusState private var isMinutesFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Exercise") {
                    Button {
                        showingExercisePicker = true
                    } label: {
                        HStack {
                            Text("Exercise")
                                .foregroundStyle(Theme.Colors.primaryText)
                            Spacer()
                            Text(exercise?.name ?? "Choose…")
                                .foregroundStyle(Theme.Colors.secondaryText)
                        }
                        .frame(minHeight: Theme.Layout.minimumTapTarget)
                    }
                }

                Section("Duration") {
                    HStack {
                        TextField("Minutes", text: $minutesText)
                            .keyboardType(.numberPad)
                            .focused($isMinutesFocused)
                        Text("min")
                            .foregroundStyle(Theme.Colors.secondaryText)
                        TextField("Seconds", text: $secondsText)
                            .keyboardType(.numberPad)
                        Text("sec")
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                }

                Section("Distance") {
                    HStack {
                        TextField("Optional", text: $distanceText)
                            .keyboardType(.decimalPad)
                        Text(distanceAbbreviation)
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                }

                Section("Calories") {
                    HStack {
                        TextField("Calories", text: $caloriesText, prompt: caloriesPrompt)
                            .keyboardType(.decimalPad)
                            .disabled(noCalorieEstimate)
                        Text("kcal")
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                    Toggle("Don't Estimate Calories", isOn: $noCalorieEstimate)
                    if let estimatedCalories, !noCalorieEstimate {
                        Text("Estimated from body weight and duration: \(Format.energy(estimatedCalories))")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                }

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                }

                Section("Date") {
                    DatePicker("Date", selection: $date, in: ...Date())
                        .labelsHidden()
                }
            }
            .navigationTitle("Log Cardio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(exercise == nil || durationSeconds <= 0)
                }
            }
            .sheet(isPresented: $showingExercisePicker) {
                ExercisePickerView(mode: .cardioOnly) { selected in
                    exercise = selected
                }
            }
            .task {
                settings = UserSettings.current(in: modelContext)
            }
            .onAppear {
                isMinutesFocused = true
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Derived values

    private var weightUnit: WeightUnit { settings?.weightUnit ?? .kilograms }

    private var distanceAbbreviation: String { weightUnit == .pounds ? "mi" : "km" }

    private var durationSeconds: Double {
        let minutes = Double(minutesText) ?? 0
        let seconds = Double(secondsText) ?? 0
        return minutes * 60 + seconds
    }

    /// Always stored metric, per the app-wide convention — converted from
    /// miles when the user's weight unit is pounds.
    private var distanceKM: Double? {
        let normalized = distanceText.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value > 0 else { return nil }
        return weightUnit == .pounds ? UnitConverter.milesToKilometres(value) : value
    }

    private var estimatedCalories: Double? {
        guard let exercise else { return nil }
        let bodyWeightKG = BodyWeightTrend.latestTrendKG(in: modelContext)
        return CardioCalories.estimate(
            exerciseName: exercise.name,
            durationSeconds: durationSeconds,
            distanceKM: distanceKM,
            bodyWeightKG: bodyWeightKG
        )
    }

    private var caloriesPrompt: Text {
        guard let estimatedCalories, !noCalorieEstimate else { return Text("") }
        return Text(Format.energy(estimatedCalories, includeUnit: false))
    }

    /// What actually gets saved: the user's explicit override if they typed
    /// one, the estimate if they left the field blank, or nil if they typed
    /// nothing and there's no estimate — or explicitly asked for none.
    private var resolvedCalories: Double? {
        if noCalorieEstimate { return nil }
        let trimmed = caloriesText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        if let typed = Double(trimmed), typed >= 0 { return typed }
        return estimatedCalories
    }

    // MARK: - Actions

    private func save() {
        guard let exercise, durationSeconds > 0 else { return }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        let entry = CardioEntry(
            performedAt: date,
            exerciseName: exercise.name,
            durationSeconds: durationSeconds,
            distanceKM: distanceKM,
            calories: resolvedCalories,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            exercise: exercise
        )
        modelContext.insert(entry)
        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    CardioEntrySheet()
        .modelContainer(SpotterSchema.previewContainer())
        .environment(\.appEnvironment, .preview())
}
