import SwiftData
import SwiftUI

/// Placeholder root for the Today tab.
///
/// Owned by workstream C. Replace this file's body with the real
/// implementation; keep the type name so `RootTabView` keeps compiling.
struct TodayView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Today",
                systemImage: "square.grid.2x2",
                description: Text("Not built yet — workstream C.")
            )
            .navigationTitle("Today")
        }
    }
}

#Preview {
    TodayView()
        .modelContainer(TallySchema.previewContainer())
        .environment(\.appEnvironment, .preview())
}
