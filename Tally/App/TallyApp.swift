import SwiftData
import SwiftUI

@main
struct TallyApp: App {
    private let modelContainer: ModelContainer
    @State private var appEnvironment: AppEnvironment

    init() {
        do {
            modelContainer = try TallySchema.makeContainer()
        } catch {
            // There is no useful recovery here: the store could not be opened,
            // so nothing the app does next would be meaningful. Crashing with
            // the underlying error is more debuggable than limping along
            // against an in-memory store the user would silently lose.
            fatalError("Could not open the Tally data store: \(error)")
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
        }
        .modelContainer(modelContainer)
    }
}
