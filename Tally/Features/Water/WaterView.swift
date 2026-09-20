import SwiftData
import SwiftUI

/// Placeholder root for the Water tab.
///
/// Owned by workstream C. Replace this file's body with the real
/// implementation; keep the type name so `RootTabView` keeps compiling.
struct WaterView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Water",
                systemImage: "drop",
                description: Text("Not built yet — workstream C.")
            )
            .navigationTitle("Water")
        }
    }
}

#Preview {
    WaterView()
        .modelContainer(TallySchema.previewContainer())
        .environment(\.appEnvironment, .preview())
}
