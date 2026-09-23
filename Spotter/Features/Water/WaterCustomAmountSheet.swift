import SwiftUI

/// A small sheet for logging an amount that isn't one of the quick-add
/// presets. The typed value is in the user's display unit; ``onAdd`` always
/// receives millilitres, since that is what gets stored.
struct WaterCustomAmountSheet: View {
    @Environment(\.dismiss) private var dismiss

    let unit: VolumeUnit
    let onAdd: (Double) -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool

    private var parsedAmount: Double? {
        let value = Double(text)
        return (value.map { $0 > 0 } ?? false) ? value : nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Amount") {
                    HStack {
                        TextField("Amount", text: $text)
                            .keyboardType(.decimalPad)
                            .focused($isFocused)
                        Text(unit.abbreviation)
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                }
            }
            .navigationTitle("Add Water")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard let parsedAmount else { return }
                        onAdd(UnitConverter.volumeToMillilitres(parsedAmount, from: unit))
                        dismiss()
                    }
                    .disabled(parsedAmount == nil)
                }
            }
            .task { isFocused = true }
        }
        .presentationDetents([.height(180)])
    }
}

#Preview {
    WaterCustomAmountSheet(unit: .fluidOunces) { _ in }
}
