import SwiftData
import SwiftUI

/// Saved meals, most recently used first. One tap logs every item into
/// `meal` (or the meal the saved meal was created for, if it set one) and
/// calls ``onLogged``. Swiping a row reveals Edit and Delete.
struct SavedMealsList: View {
    let meal: Meal
    var onLogged: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar

    @Query(sort: [SortDescriptor(\SavedMeal.lastUsedAt, order: .reverse)])
    private var savedMeals: [SavedMeal]

    @State private var editingMeal: SavedMeal?

    var body: some View {
        Group {
            if savedMeals.isEmpty {
                ContentUnavailableView(
                    "No Saved Meals",
                    systemImage: "tray.and.arrow.down",
                    description: Text("Save a meal's entries from the diary to reuse them here.")
                )
            } else {
                List(savedMeals) { savedMeal in
                    SavedMealRow(savedMeal: savedMeal)
                        .contentShape(Rectangle())
                        .onTapGesture { log(savedMeal) }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                modelContext.delete(savedMeal)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                editingMeal = savedMeal
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(Theme.Colors.accent)
                        }
                }
                .listStyle(.plain)
            }
        }
        .sheet(item: $editingMeal) { savedMeal in
            SavedMealEditorView(savedMeal: savedMeal)
        }
    }

    private func log(_ savedMeal: SavedMeal) {
        let neededIDs = Set(savedMeal.items.compactMap(\.foodID))
        var foodsByID: [UUID: FoodItem] = [:]
        if !neededIDs.isEmpty {
            let allFoods = (try? modelContext.fetch(FetchDescriptor<FoodItem>())) ?? []
            for food in allFoods where neededIDs.contains(food.id) {
                foodsByID[food.id] = food
            }
        }

        let targetMeal = savedMeal.defaultMeal ?? meal
        let entries = SavedMealLogging.entries(
            for: savedMeal.orderedItems,
            resolvingFoods: foodsByID,
            meal: targetMeal,
            calendar: calendar
        )
        for entry in entries {
            modelContext.insert(entry)
        }
        savedMeal.markUsed()
        WidgetSnapshotWriter.refresh(in: modelContext)
        onLogged()
    }
}

private struct SavedMealRow: View {
    let savedMeal: SavedMeal

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(savedMeal.name)
                Text("\(savedMeal.items.count) item\(savedMeal.items.count == 1 ? "" : "s")")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
            Spacer()
            Text(Format.energy(savedMeal.totalNutrients.effectiveKcal))
                .font(Theme.Typography.setValue)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
        .frame(minHeight: Theme.Layout.minimumTapTarget)
    }
}

#Preview {
    let container = SpotterSchema.previewContainer()
    let savedMeal = SavedMeal(
        name: "Protein Shake + Oats",
        items: [
            SavedMealItem(
                order: 0,
                foodName: "Protein Powder",
                quantity: 1,
                servingLabel: "1 scoop",
                servingGramWeight: 30,
                nutrientsSnapshot: Nutrients(kcal: 120, proteinG: 24)
            ),
            SavedMealItem(
                order: 1,
                foodName: "Oats",
                quantity: 1,
                servingLabel: "50 g",
                servingGramWeight: 50,
                nutrientsSnapshot: Nutrients(kcal: 190, proteinG: 7, carbsG: 33, fatG: 3.5)
            ),
        ]
    )
    container.mainContext.insert(savedMeal)
    return SavedMealsList(meal: .breakfast, onLogged: {})
        .modelContainer(container)
        .environment(\.appEnvironment, .preview())
}
