import SwiftData
import SwiftUI

/// Collects body stats and writes the four daily nutrition goals on
/// ``UserSettings``.
///
/// Inputs are stored back onto `UserSettings` alongside the goals (see the
/// schema step's "Goal calculator inputs"), so recalculating later — as the
/// weight trend moves — is a single "Apply" tap rather than re-entering
/// everything.
///
/// This screen only ever writes the goals through `apply()`, following the
/// plan's note that the "Apply" path should stay the one place the four goal
/// fields get written, so a Phase 3 coach-assigned target can reuse the same
/// entry point.
struct GoalCalculatorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var settings: UserSettings

    /// Current weight in kilograms, from the smoothed trend. Nil when there
    /// are no weigh-ins at all, which is the only case manual entry is
    /// required for — a single weigh-in already comes back as its own trend
    /// value, so there is no separate "else the last weigh-in" branch to
    /// model here.
    @State private var knownWeightKG: Double?
    @State private var weightText: String = ""
    @State private var alsoSaveAsWeighIn = true

    @State private var heightCMText: String = ""
    @State private var heightFeetText: String = ""
    @State private var heightInchesText: String = ""

    @State private var birthYear: Int
    @State private var sex: BiologicalSex?
    @State private var activityLevel: ActivityLevel
    @State private var weightGoal: WeightGoal
    @State private var weeklyRateKG: Double
    @State private var proteinGPerKG: Double

    private let currentYear: Int

    /// `now` is injectable so age math is deterministic in previews and
    /// (indirectly, via `GoalCalculator`) in tests.
    init(settings: UserSettings, now: Date = Date(), calendar: Calendar = .current) {
        self.settings = settings
        let year = calendar.component(.year, from: now)
        self.currentYear = year

        _birthYear = State(initialValue: settings.birthYear ?? (year - 30))
        _sex = State(initialValue: settings.sex)
        _activityLevel = State(initialValue: settings.activityLevel ?? .moderate)
        _weightGoal = State(initialValue: settings.weightGoal ?? .maintain)
        _weeklyRateKG = State(initialValue: settings.weeklyRateKG ?? 0.5)
        _proteinGPerKG = State(initialValue: settings.proteinGPerKG ?? 1.6)
    }

    private static let weeklyRateOptions: [Double] = [0.25, 0.5, 0.75, 1.0]

    /// A reasonable span of birth years, anchored to the injected current
    /// year rather than a hardcoded range, so it doesn't quietly go stale.
    private var birthYearRange: ClosedRange<Int> {
        (currentYear - 100)...(currentYear - 5)
    }

    var body: some View {
        NavigationStack {
            Form {
                weightSection
                heightSection
                aboutYouSection
                activitySection
                goalSection
                proteinSection
                resultSection
                Section {
                    Text("Estimates only, not medical advice. Talk to a doctor or dietitian before making major changes to your diet.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
            }
            .navigationTitle("Calculate Goals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { apply() }
                        .disabled(result == nil)
                }
            }
            .task {
                knownWeightKG = BodyWeightTrend.latestTrendKG(in: modelContext)
                seedWeightText()
                seedHeightText()
            }
        }
    }

    // MARK: - Weight

    private var weightSection: some View {
        Section("Weight") {
            HStack {
                TextField("Weight", text: $weightText)
                    .keyboardType(.decimalPad)
                Text(settings.weightUnit.abbreviation)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
            if knownWeightKG != nil {
                Text("Prefilled from your weight trend.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
            } else {
                Toggle("Also save as a weigh-in", isOn: $alsoSaveAsWeighIn)
            }
        }
    }

    // MARK: - Height

    private var heightSection: some View {
        Section("Height") {
            if settings.weightUnit == .pounds {
                HStack {
                    TextField("Feet", text: $heightFeetText)
                        .keyboardType(.numberPad)
                    Text("ft").foregroundStyle(Theme.Colors.secondaryText)
                    TextField("Inches", text: $heightInchesText)
                        .keyboardType(.numberPad)
                    Text("in").foregroundStyle(Theme.Colors.secondaryText)
                }
            } else {
                HStack {
                    TextField("Height", text: $heightCMText)
                        .keyboardType(.numberPad)
                    Text("cm").foregroundStyle(Theme.Colors.secondaryText)
                }
            }
        }
    }

    // MARK: - About you

    private var aboutYouSection: some View {
        Section("About You") {
            Picker("Birth Year", selection: $birthYear) {
                ForEach(Array(birthYearRange), id: \.self) { year in
                    Text(String(year)).tag(year)
                }
            }
            Picker("Sex", selection: $sex) {
                Text("Prefer Not to Say").tag(BiologicalSex?.none)
                ForEach(BiologicalSex.allCases) { option in
                    Text(option.displayName).tag(BiologicalSex?.some(option))
                }
            }
        }
    }

    // MARK: - Activity

    private var activitySection: some View {
        Section {
            Picker("Activity Level", selection: $activityLevel) {
                ForEach(ActivityLevel.allCases) { level in
                    Text(level.displayName).tag(level)
                }
            }
            Text(activityLevel.detail)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
        } header: {
            Text("Activity")
        }
    }

    // MARK: - Goal

    private var goalSection: some View {
        Section("Goal") {
            Picker("Goal", selection: $weightGoal) {
                ForEach(WeightGoal.allCases) { goal in
                    Text(goal.displayName).tag(goal)
                }
            }
            if weightGoal != .maintain {
                Picker("Weekly Rate", selection: $weeklyRateKG) {
                    ForEach(Self.weeklyRateOptions, id: \.self) { rate in
                        Text("\(QuantityFormatter.string(from: rate)) kg/wk").tag(rate)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    // MARK: - Protein

    private var proteinSection: some View {
        Section("Protein Target") {
            Stepper(value: $proteinGPerKG, in: 1.2...2.4, step: 0.1) {
                LabeledContent("Protein", value: String(format: "%.1f g/kg", proteinGPerKG))
            }
        }
    }

    // MARK: - Result

    private var resultSection: some View {
        Section("Estimated Targets") {
            if let result {
                LabeledContent("BMR", value: Format.energy(result.bmr))
                LabeledContent("Maintenance", value: Format.energy(result.maintenanceKcal))
                LabeledContent("Daily Target", value: Format.energy(result.targetKcal))
                LabeledContent("Protein", value: Format.grams(result.proteinG))
                LabeledContent("Fat", value: Format.grams(result.fatG))
                LabeledContent("Carbs", value: Format.grams(result.carbsG))
                if result.isClamped {
                    Text("Target raised to a safe minimum for your stats.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.warning)
                }
            } else {
                Text("Enter your weight and height to see an estimate.")
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
        }
    }

    // MARK: - Derived input

    private var weightKG: Double? {
        let normalized = weightText.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value > 0 else { return nil }
        return UnitConverter.weightToKilograms(value, from: settings.weightUnit)
    }

    private var heightCM: Double? {
        if settings.weightUnit == .pounds {
            let feet = Double(heightFeetText) ?? 0
            let inches = Double(heightInchesText) ?? 0
            let totalInches = feet * 12 + inches
            guard totalInches > 0 else { return nil }
            return totalInches * 2.54
        } else {
            guard let cm = Double(heightCMText), cm > 0 else { return nil }
            return cm
        }
    }

    private var result: GoalCalculator.Result? {
        guard let weightKG, let heightCM else { return nil }
        let input = GoalCalculator.Input(
            weightKG: weightKG,
            heightCM: heightCM,
            birthYear: birthYear,
            sex: sex,
            activityLevel: activityLevel,
            weightGoal: weightGoal,
            weeklyRateKG: weeklyRateKG,
            proteinGPerKG: proteinGPerKG,
            currentYear: currentYear
        )
        return GoalCalculator.calculate(input)
    }

    // MARK: - Seeding

    private func seedWeightText() {
        let unit = settings.weightUnit
        if let knownWeightKG {
            weightText = QuantityFormatter.string(from: UnitConverter.weight(knownWeightKG, in: unit))
        } else if let goalWeightKG = settings.goalWeightKG {
            // No weigh-in at all yet: fall back to a goal weight if one was
            // set some other way, otherwise leave it blank for manual entry.
            weightText = QuantityFormatter.string(from: UnitConverter.weight(goalWeightKG, in: unit))
        }
    }

    private func seedHeightText() {
        guard let existingCM = settings.heightCM else { return }
        if settings.weightUnit == .pounds {
            let totalInches = existingCM / 2.54
            let feet = (totalInches / 12).rounded(.down)
            let inches = (totalInches - feet * 12).rounded()
            heightFeetText = String(format: "%.0f", feet)
            heightInchesText = String(format: "%.0f", inches)
        } else {
            heightCMText = String(format: "%.0f", existingCM)
        }
    }

    // MARK: - Apply

    private func apply() {
        guard let result, let weightKG, let heightCM else { return }

        settings.dailyKcalGoal = result.targetKcal
        settings.dailyProteinGoalG = result.proteinG
        settings.dailyCarbsGoalG = result.carbsG
        settings.dailyFatGoalG = result.fatG

        settings.heightCM = heightCM
        settings.birthYear = birthYear
        settings.sex = sex
        settings.activityLevel = activityLevel
        settings.weightGoal = weightGoal
        settings.weeklyRateKG = weeklyRateKG
        settings.proteinGPerKG = proteinGPerKG

        if knownWeightKG == nil && alsoSaveAsWeighIn {
            let measurement = BodyMeasurement(type: .bodyWeight, value: weightKG)
            modelContext.insert(measurement)
        }

        dismiss()
    }
}

#Preview {
    let container = TallySchema.previewContainer()
    let settings = UserSettings.current(in: container.mainContext)

    return GoalCalculatorView(settings: settings)
        .modelContainer(container)
        .environment(\.appEnvironment, .preview())
}
