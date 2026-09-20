import SwiftData
import SwiftUI

/// Root of the Settings tab.
///
/// Reads and writes the single `UserSettings` row via
/// `UserSettings.current(in:)`. `@Bindable` on that row is what lets every
/// control below bind directly to a property (`$settings.dailyKcalGoal`,
/// `$settings.weightUnit`, ...): SwiftData models are `Observable`, so a
/// computed property whose setter mutates a tracked stored property (like
/// `weightUnit` wrapping `weightUnitRaw`) still participates correctly.
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsList: [UserSettings]

    private var settings: UserSettings {
        settingsList.first ?? UserSettings.current(in: modelContext)
    }

    var body: some View {
        NavigationStack {
            SettingsForm(settings: settings)
                .navigationTitle("Settings")
        }
    }
}

private struct SettingsForm: View {
    @Bindable var settings: UserSettings
    @State private var showingPresetEditor = false

    var body: some View {
        Form {
            goalsSection
            unitsSection
            workoutSection
            waterPresetsSection
            foodDataSection
            aboutSection
        }
        .sheet(isPresented: $showingPresetEditor) {
            WaterPresetEditorView(settings: settings, unit: settings.volumeUnit)
        }
    }

    // MARK: - Goals

    private var goalsSection: some View {
        Section("Goals") {
            LabeledContent("Calories") {
                TextField("kcal", value: $settings.dailyKcalGoal, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("Protein") {
                HStack {
                    TextField("g", value: $settings.dailyProteinGoalG, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                    Text("g").foregroundStyle(Theme.Colors.secondaryText)
                }
            }
            LabeledContent("Carbs") {
                HStack {
                    TextField("g", value: $settings.dailyCarbsGoalG, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                    Text("g").foregroundStyle(Theme.Colors.secondaryText)
                }
            }
            LabeledContent("Fat") {
                HStack {
                    TextField("g", value: $settings.dailyFatGoalG, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                    Text("g").foregroundStyle(Theme.Colors.secondaryText)
                }
            }
            LabeledContent("Water") {
                HStack {
                    TextField("Amount", value: waterGoalBinding, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                    Text(settings.volumeUnit.abbreviation).foregroundStyle(Theme.Colors.secondaryText)
                }
            }
        }
    }

    /// The water goal displayed and typed in the user's preferred unit, while
    /// `UserSettings.dailyWaterGoalML` itself always stays millilitres.
    private var waterGoalBinding: Binding<Double> {
        Binding(
            get: { UnitConverter.volume(settings.dailyWaterGoalML, in: settings.volumeUnit) },
            set: { settings.dailyWaterGoalML = UnitConverter.volumeToMillilitres($0, from: settings.volumeUnit) }
        )
    }

    // MARK: - Units

    private var unitsSection: some View {
        Section("Units") {
            Picker("Weight", selection: $settings.weightUnit) {
                ForEach(WeightUnit.allCases) { unit in
                    Text(unit.displayName).tag(unit)
                }
            }
            Picker("Volume", selection: $settings.volumeUnit) {
                ForEach(VolumeUnit.allCases) { unit in
                    Text(unit.displayName).tag(unit)
                }
            }
        }
    }

    // MARK: - Workout preferences

    private var workoutSection: some View {
        Section("Workout Preferences") {
            Stepper(value: $settings.restTimerSeconds, in: 15...600, step: 15) {
                LabeledContent("Rest Timer", value: Format.duration(TimeInterval(settings.restTimerSeconds)))
            }
            Toggle("Auto-Start Rest Timer", isOn: $settings.autoStartRestTimer)
            Toggle("Rest Timer Notifications", isOn: $settings.restTimerNotifications)
            Picker("1RM Formula", selection: $settings.oneRepMaxFormula) {
                ForEach(OneRepMaxFormula.allCases) { formula in
                    Text(formula.displayName).tag(formula)
                }
            }
            Toggle("Keep Screen Awake", isOn: $settings.keepScreenAwakeDuringWorkout)
        }
    }

    // MARK: - Water presets

    private var waterPresetsSection: some View {
        Section("Water Presets") {
            ForEach(settings.waterPresets) { preset in
                HStack {
                    Image(systemName: preset.symbolName)
                        .foregroundStyle(Theme.Colors.water)
                    Text(preset.label)
                    Spacer()
                    Text(Format.volume(preset.volumeML, in: settings.volumeUnit))
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
            }
            Button("Edit Presets") { showingPresetEditor = true }
        }
    }

    // MARK: - Food data

    private var foodDataSection: some View {
        Section {
            TextField("Contact (email or URL)", text: $settings.openFoodFactsContact)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            LabeledContent("USDA Search") {
                Text(AppConfiguration.isUSDAConfigured ? "Configured" : "Not Configured")
                    .foregroundStyle(AppConfiguration.isUSDAConfigured ? Theme.Colors.success : Theme.Colors.secondaryText)
            }
        } header: {
            Text("Food Data")
        } footer: {
            Text(foodDataFooter)
        }
    }

    private var foodDataFooter: String {
        var text = "Open Food Facts requires every request to identify the app making it. "
            + "Your contact lets them reach you if traffic from Tally ever causes a problem, "
            + "instead of blocking it outright."
        if !AppConfiguration.isUSDAConfigured {
            text += " USDA search needs a free API key — see the project README for how to add one."
        }
        return text
    }

    // MARK: - About

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: AppConfiguration.appVersion)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Link("Open Food Facts", destination: URL(string: "https://world.openfoodfacts.org")!)
                Text("Product data from Open Food Facts, licensed under the Open Database License (ODbL). Contents are used and shared under the same terms.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Link("USDA FoodData Central", destination: URL(string: "https://fdc.nal.usda.gov")!)
                Text("Generic food data from USDA FoodData Central, U.S. government work released as CC0 / public domain.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(TallySchema.previewContainer())
        .environment(\.appEnvironment, .preview())
}
