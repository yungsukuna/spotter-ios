import SwiftData
import SwiftUI

/// Placeholder root for the Settings tab.
///
/// Owned by workstream C. Replace this file's body with the real
/// implementation; keep the type name so `RootTabView` keeps compiling.
struct SettingsView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Settings",
                systemImage: "gearshape",
                description: Text("Not built yet — workstream C.")
            )
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(TallySchema.previewContainer())
        .environment(\.appEnvironment, .preview())
}
