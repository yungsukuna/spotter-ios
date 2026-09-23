import SwiftData
import SwiftUI

/// Add or edit a single weigh-in.
///
/// The text field and its label are always in the user's display unit;
/// storage is always kilograms, converted at save time via
/// `UnitConverter.weightToKilograms` — the same edges-only rule every other
/// stored measurement in the app follows.
struct WeighInSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    /// Nil creates a new weigh-in; non-nil edits it in place.
    var existing: BodyMeasurement?
    let unit: WeightUnit
    /// Prefill for a new weigh-in, already converted to `unit`. Ignored when
    /// editing an existing entry, which prefills from its own value instead.
    var lastValueInUnit: Double?

    @State private var text: String
    @State private var date: Date
    @FocusState private var isFocused: Bool

    init(existing: BodyMeasurement? = nil, unit: WeightUnit, lastValueInUnit: Double? = nil) {
        self.existing = existing
        self.unit = unit
        self.lastValueInUnit = lastValueInUnit

        if let existing {
            _text = State(initialValue: QuantityFormatter.string(from: UnitConverter.weight(existing.value, in: unit)))
            _date = State(initialValue: existing.recordedAt)
        } else {
            _text = State(initialValue: lastValueInUnit.map(QuantityFormatter.string(from:)) ?? "")
            _date = State(initialValue: Date())
        }
    }

    private var parsedValue: Double? {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        let value = Double(normalized)
        return (value.map { $0 > 0 } ?? false) ? value : nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Weight") {
                    HStack {
                        TextField("Weight", text: $text)
                            .keyboardType(.decimalPad)
                            .focused($isFocused)
                        Text(unit.abbreviation)
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                }
                Section("Date") {
                    DatePicker("Date", selection: $date, in: ...Date())
                        .labelsHidden()
                }
            }
            .navigationTitle(existing == nil ? "Add Weigh-In" : "Edit Weigh-In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(parsedValue == nil)
                }
            }
            .task { isFocused = true }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        guard let parsedValue else { return }
        let kg = UnitConverter.weightToKilograms(parsedValue, from: unit)

        if let existing {
            existing.value = kg
            existing.recordedAt = date
            existing.dayKey = DayKey.make(from: date)
        } else {
            let measurement = BodyMeasurement(recordedAt: date, type: .bodyWeight, value: kg)
            modelContext.insert(measurement)
        }

        dismiss()
    }
}

#Preview {
    WeighInSheet(unit: .kilograms, lastValueInUnit: 82.5)
        .modelContainer(TallySchema.previewContainer())
        .environment(\.appEnvironment, .preview())
}
