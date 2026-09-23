import SwiftData
import SwiftUI

/// Per-side plate breakdown for a barbell set's target weight.
///
/// Reachable from a set row's context menu, never as a sub-screen of the
/// logging flow — it is a sheet, dismissed straight back to the set row it
/// was opened from. Editing the bar weight here writes
/// `UserSettings.barbellWeightKG`, so it stays correct for every barbell
/// exercise afterwards.
struct PlateCalculatorSheet: View {
    /// The set's target weight, in kilograms.
    var targetKG: Double
    var weightUnit: WeightUnit

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var settings: UserSettings?
    @State private var barWeightText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Target") {
                    LabeledContent("Weight", value: Format.weight(targetKG, in: weightUnit))
                }
                Section("Bar") {
                    HStack {
                        TextField("Bar Weight", text: $barWeightText)
                            .keyboardType(.decimalPad)
                        Text(weightUnit.abbreviation)
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                }
                Section("Per Side") {
                    if loading.plates.isEmpty {
                        Text("No plates needed")
                            .foregroundStyle(Theme.Colors.secondaryText)
                    } else {
                        HStack(spacing: Theme.Spacing.sm) {
                            ForEach(Array(loading.plates.enumerated()), id: \.offset) { _, plate in
                                plateChip(plate)
                            }
                        }
                    }
                    LabeledContent("Achievable", value: displayText(loading.achieved))
                    if loading.remainder > 0.01 {
                        Text("Off by \(displayText(loading.remainder))")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.warning)
                    }
                }
            }
            .navigationTitle("Plate Calculator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveBarWeight()
                        dismiss()
                    }
                    .frame(minHeight: Theme.Layout.minimumTapTarget)
                }
            }
            .task {
                let current = UserSettings.current(in: modelContext)
                settings = current
                barWeightText = QuantityFormatter.string(
                    from: UnitConverter.weight(barWeightKG(for: current), in: weightUnit)
                )
            }
        }
        .presentationDetents([.medium])
    }

    private func barWeightKG(for settings: UserSettings) -> Double {
        settings.barbellWeightKG ?? PlateCalculator.defaultBarWeightKG(for: weightUnit)
    }

    /// The bar weight currently typed, in kilograms, falling back to the
    /// stored/default bar weight while the field is empty or unparsable.
    private var enteredBarKG: Double {
        let trimmed = barWeightText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let typed = Double(trimmed), typed >= 0 else {
            if let settings { return barWeightKG(for: settings) }
            return PlateCalculator.defaultBarWeightKG(for: weightUnit)
        }
        return UnitConverter.weightToKilograms(typed, from: weightUnit)
    }

    /// Target, bar and the resulting per-side loading, all computed in the
    /// display unit — see the note on `PlateCalculator.perSide`.
    private var loading: PlateCalculator.Loading {
        let targetDisplay = UnitConverter.weight(targetKG, in: weightUnit)
        let barDisplay = UnitConverter.weight(enteredBarKG, in: weightUnit)
        return PlateCalculator.perSide(
            target: targetDisplay,
            bar: barDisplay,
            plates: PlateCalculator.plates(for: weightUnit)
        )
    }

    /// `loading`'s values are already in the display unit, so this only
    /// formats — it must not go through `Format.weight`, which expects kg.
    private func displayText(_ value: Double) -> String {
        "\(QuantityFormatter.string(from: value)) \(weightUnit.abbreviation)"
    }

    private func plateChip(_ plate: Double) -> some View {
        Text(QuantityFormatter.string(from: plate))
            .font(Theme.Typography.setValue)
            .frame(minWidth: Theme.Layout.minimumTapTarget, minHeight: Theme.Layout.minimumTapTarget)
            .background(Theme.Colors.workout.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
    }

    private func saveBarWeight() {
        guard let settings else { return }
        settings.barbellWeightKG = enteredBarKG
        try? modelContext.save()
    }
}

#Preview {
    PlateCalculatorSheet(targetKG: 100, weightUnit: .kilograms)
        .modelContainer(TallySchema.previewContainer())
        .environment(\.appEnvironment, .preview())
}
