import SwiftUI

/// Log calories (and optionally macros) without picking a food — a
/// restaurant meal, a homemade dish, or anything not worth cataloguing.
///
/// See ``QuickAdd`` for the parsing and entry-building logic behind this
/// view.
struct QuickAddSheet: View {
    let meal: Meal

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var kcalText = ""
    @State private var proteinText = ""
    @State private var carbsText = ""
    @State private var fatText = ""

    private var nutrients: Nutrients? {
        QuickAdd.makeNutrients(
            kcalText: kcalText,
            proteinText: proteinText,
            carbsText: carbsText,
            fatText: fatText
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text(QuickAdd.defaultName))
                }

                Section("Calories") {
                    numberField("Calories", text: $kcalText)
                }

                Section("Macros (optional)") {
                    numberField("Protein (g)", text: $proteinText)
                    numberField("Carbs (g)", text: $carbsText)
                    numberField("Fat (g)", text: $fatText)
                }
            }
            .navigationTitle("Quick Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(nutrients == nil)
                }
            }
        }
    }

    @ViewBuilder
    private func numberField(_ title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("—", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
        .frame(minHeight: Theme.Layout.minimumTapTarget)
    }

    private func save() {
        guard let nutrients else { return }
        let entry = QuickAdd.makeEntry(name: name, nutrients: nutrients, meal: meal)
        modelContext.insert(entry)
        WidgetSnapshotWriter.refresh(in: modelContext)
        dismiss()
    }
}

#Preview {
    QuickAddSheet(meal: .lunch)
        .modelContainer(SpotterSchema.previewContainer())
        .environment(\.appEnvironment, .preview())
}
