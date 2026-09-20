import SwiftUI

/// Sheet for editing the quick-add buttons on the Water tab.
///
/// Mutates `settings.waterPresets` directly — `UserSettings` is a SwiftData
/// model, so appending or removing from the array and saving the context is
/// all persistence requires.
struct WaterPresetEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let settings: UserSettings
    let unit: VolumeUnit

    @State private var newLabel = ""
    @State private var newAmountText = ""
    @State private var newSymbol = "drop"

    /// A small, deliberately limited set of SF Symbols relevant to drinks —
    /// a free-text symbol name field would let a typo silently produce no
    /// icon at all.
    private static let symbolChoices = [
        "drop", "cup.and.saucer", "waterbottle", "waterbottle.fill", "mug", "takeoutbag.and.cup.and.straw",
    ]

    private var parsedAmount: Double? {
        let value = Double(newAmountText)
        return (value.map { $0 > 0 } ?? false) ? value : nil
    }

    private var canAdd: Bool {
        !newLabel.trimmingCharacters(in: .whitespaces).isEmpty && parsedAmount != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Presets") {
                    if settings.waterPresets.isEmpty {
                        Text("No presets yet.")
                            .foregroundStyle(Theme.Colors.secondaryText)
                    } else {
                        ForEach(settings.waterPresets) { preset in
                            HStack {
                                Image(systemName: preset.symbolName)
                                    .foregroundStyle(Theme.Colors.water)
                                Text(preset.label)
                                Spacer()
                                Text(Format.volume(preset.volumeML, in: unit))
                                    .foregroundStyle(Theme.Colors.secondaryText)
                            }
                        }
                        .onDelete(perform: deletePresets)
                    }
                }

                Section("Add preset") {
                    TextField("Label", text: $newLabel)
                    HStack {
                        TextField("Amount", text: $newAmountText)
                            .keyboardType(.decimalPad)
                        Text(unit.abbreviation)
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                    Picker("Icon", selection: $newSymbol) {
                        ForEach(Self.symbolChoices, id: \.self) { symbol in
                            Image(systemName: symbol).tag(symbol)
                        }
                    }
                    .pickerStyle(.segmented)
                    Button("Add Preset") { addPreset() }
                        .disabled(!canAdd)
                }
            }
            .navigationTitle("Water Presets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func deletePresets(at offsets: IndexSet) {
        settings.waterPresets.remove(atOffsets: offsets)
        try? modelContext.save()
    }

    private func addPreset() {
        guard let parsedAmount else { return }
        let trimmedLabel = newLabel.trimmingCharacters(in: .whitespaces)
        guard !trimmedLabel.isEmpty else { return }
        let volumeML = UnitConverter.volumeToMillilitres(parsedAmount, from: unit)
        settings.waterPresets.append(WaterPreset(label: trimmedLabel, volumeML: volumeML, symbolName: newSymbol))
        try? modelContext.save()
        newLabel = ""
        newAmountText = ""
    }
}

#Preview {
    WaterPresetEditorView(settings: UserSettings(), unit: .millilitres)
        .modelContainer(TallySchema.previewContainer())
}
