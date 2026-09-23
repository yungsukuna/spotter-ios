import SwiftData
import SwiftUI

@main
struct SpotterApp: App {
    private let modelContainer: ModelContainer
    @State private var appEnvironment: AppEnvironment

    init() {
        do {
            modelContainer = try SpotterSchema.makeContainer()
        } catch {
            // There is no useful recovery here: the store could not be opened,
            // so nothing the app does next would be meaningful. Crashing with
            // the underlying error is more debuggable than limping along
            // against an in-memory store the user would silently lose.
            fatalError("Could not open the Spotter data store: \(error)")
        }

        let settings = UserSettings.current(in: modelContainer.mainContext)
        let foodDataSource = CompositeFoodDataSource(
            openFoodFacts: OpenFoodFactsClient(contact: settings.openFoodFactsContact),
            usda: USDAFoodDataCentralClient()
        )
        _appEnvironment = State(initialValue: AppEnvironment(foodDataSource: foodDataSource))
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(\.appEnvironment, appEnvironment)
                .task {
                    // Idempotent: adds only exercises that are missing, so it
                    // is safe on every launch and picks up library additions
                    // shipped in later versions.
                    ExerciseLibrary.seedIfNeeded(in: modelContainer.mainContext)
                }
                .onScenePhaseBackground {
                    WidgetSnapshotWriter.refresh(in: modelContainer.mainContext)
                }
        }
        .modelContainer(modelContainer)
    }
}

/// Runs `action` whenever the scene enters the background — leaving the app,
/// locking the device, or switching away. Factored into a modifier rather
/// than putting `@Environment(\.scenePhase)` directly on `SpotterApp` (a
/// `struct App` cannot hold `@Environment`) or on `RootTabView` (which
/// belongs to another workstream).
private struct ScenePhaseBackgroundModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .background {
                    action()
                }
            }
    }
}

private extension View {
    func onScenePhaseBackground(_ action: @escaping () -> Void) -> some View {
        modifier(ScenePhaseBackgroundModifier(action: action))
    }
}
