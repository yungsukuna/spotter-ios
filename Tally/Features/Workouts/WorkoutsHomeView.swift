import SwiftData
import SwiftUI

/// Placeholder root for the Workouts tab.
///
/// Owned by workstream B. Replace this file's body with the real
/// implementation; keep the type name so `RootTabView` keeps compiling.
struct WorkoutsHomeView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Workouts",
                systemImage: "dumbbell",
                description: Text("Not built yet — workstream B.")
            )
            .navigationTitle("Workouts")
        }
    }
}

#Preview {
    WorkoutsHomeView()
        .modelContainer(TallySchema.previewContainer())
        .environment(\.appEnvironment, .preview())
}
