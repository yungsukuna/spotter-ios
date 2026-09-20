import SwiftData
import SwiftUI

/// Editor for the daily nutrition targets stored on ``UserSettings``.
///
/// `UserSettings` is a singleton row fetched via ``UserSettings/current(in:)``;
/// this screen mutates that row in place rather than working from a local
/// copy, so there is no separate "commit" step beyond dismissing.
struct GoalsEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var settings: UserSettings?

    var body: some View {
        NavigationStack {
            Group {
                if let settings {
                    Form {
                        Section("Daily Goals") {
                            goalField("Calories", value: binding(for: settings, \.dailyKcalGoal))
                            goalField("Protein (g)", value: binding(for: settings, \.dailyProteinGoalG))
                            goalField("Carbs (g)", value: binding(for: settings, \.dailyCarbsGoalG))
                            goalField("Fat (g)", value: binding(for: settings, \.dailyFatGoalG))
                        }
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Nutrition Goals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                if settings == nil {
                    settings = UserSettings.current(in: modelContext)
                }
            }
        }
    }

    @ViewBuilder
    private func goalField(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(Theme.Colors.secondaryText)
                .frame(width: 100)
        }
    }

    private func binding(
        for settings: UserSettings,
        _ keyPath: ReferenceWritableKeyPath<UserSettings, Double>
    ) -> Binding<Double> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { settings[keyPath: keyPath] = $0 }
        )
    }
}

#Preview {
    GoalsEditorView()
        .modelContainer(TallySchema.previewContainer())
        .environment(\.appEnvironment, .preview())
}
