import SwiftData
import SwiftUI

/// The five top-level sections.
///
/// Each tab's root view lives in its own folder under `Features/` and is owned
/// by exactly one workstream, so the tabs can be built independently.
struct RootTabView: View {
    @State private var selection: TabSelection = .today

    /// Named `TabSelection` rather than `Tab`, which would shadow SwiftUI's own
    /// `Tab` view type and break the builder below.
    enum TabSelection: Hashable {
        case today, food, workouts, water, settings
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Today", systemImage: "square.grid.2x2", value: TabSelection.today) {
                TodayView()
            }

            Tab("Food", systemImage: "fork.knife", value: TabSelection.food) {
                NutritionDiaryView()
            }

            Tab("Workouts", systemImage: "dumbbell", value: TabSelection.workouts) {
                WorkoutsHomeView()
            }

            Tab("Water", systemImage: "drop", value: TabSelection.water) {
                WaterView()
            }

            Tab("Settings", systemImage: "gearshape", value: TabSelection.settings) {
                SettingsView()
            }
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(SpotterSchema.previewContainer())
        .environment(\.appEnvironment, .preview())
}
