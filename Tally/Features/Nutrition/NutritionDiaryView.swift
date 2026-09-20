import SwiftData
import SwiftUI

/// Placeholder root for the Food tab.
///
/// Owned by workstream A. Replace this file's body with the real
/// implementation; keep the type name so `RootTabView` keeps compiling.
struct NutritionDiaryView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Food",
                systemImage: "fork.knife",
                description: Text("Not built yet — workstream A.")
            )
            .navigationTitle("Food")
        }
    }
}

#Preview {
    NutritionDiaryView()
        .modelContainer(TallySchema.previewContainer())
        .environment(\.appEnvironment, .preview())
}
