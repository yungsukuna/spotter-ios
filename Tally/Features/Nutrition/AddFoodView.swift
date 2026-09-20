import SwiftData
import SwiftUI

/// Which section of the add-food screen is showing.
private enum AddFoodTab: String, CaseIterable, Identifiable {
    case search, recent, frequent, myFoods

    var id: String { rawValue }

    var title: String {
        switch self {
        case .search: "Search"
        case .recent: "Recent"
        case .frequent: "Frequent"
        case .myFoods: "My Foods"
        }
    }
}

/// The next screen to present, chosen by whatever the user tapped. A single
/// sheet driven by one optional value, rather than several booleans, so only
/// one destination can ever be presented at a time.
private struct AddFoodDestination: Identifiable {
    let id = UUID()
    let kind: Kind

    enum Kind {
        case detail(FoodDetailView.Source)
        case customEntry(existingFood: FoodItem?, name: String, brand: String?, barcode: String?)
    }
}

/// Search, browse, or scan a food to add to one meal.
///
/// A result that ``FoodRecord/lacksNutrition`` is routed to manual entry
/// instead of the portion picker — logging a portion of a food with no
/// calorie figure would silently contribute nothing to the day's total, which
/// is worse than asking the user to type in what's on the label.
///
/// Barcode scanning is owned by a different workstream. This screen only
/// exposes the hook: ``onScanRequested``. When nil (e.g. in previews, or
/// until that workstream lands), tapping the scan button shows a placeholder
/// explanation instead of doing nothing.
struct AddFoodView: View {
    let meal: Meal
    var onScanRequested: (() -> Void)?

    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var tab: AddFoodTab = .search
    @State private var searchModel: FoodSearchModel?
    @State private var destination: AddFoodDestination?
    @State private var showingScannerPlaceholder = false

    @Query(
        filter: #Predicate<FoodItem> { $0.lastUsedAt != nil },
        sort: [SortDescriptor(\.lastUsedAt, order: .reverse)]
    )
    private var recentFoods: [FoodItem]

    @Query(
        filter: #Predicate<FoodItem> { $0.useCount > 0 },
        sort: [SortDescriptor(\.useCount, order: .reverse)]
    )
    private var frequentFoods: [FoodItem]

    @Query(
        filter: #Predicate<FoodItem> { $0.isCustom },
        sort: [SortDescriptor(\.name)]
    )
    private var myFoods: [FoodItem]

    init(meal: Meal, onScanRequested: (() -> Void)? = nil) {
        self.meal = meal
        self.onScanRequested = onScanRequested
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Section", selection: $tab) {
                    ForEach(AddFoodTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding([.horizontal, .top], Theme.Spacing.lg)

                switch tab {
                case .search:
                    searchTab
                case .recent:
                    foodList(recentFoods, emptyTitle: "No recent foods", emptyIcon: "clock")
                case .frequent:
                    foodList(frequentFoods, emptyTitle: "No frequent foods", emptyIcon: "chart.bar")
                case .myFoods:
                    myFoodsTab
                }
            }
            .navigationTitle("Add to \(meal.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(item: $destination) { destination in
                switch destination.kind {
                case .detail(let source):
                    FoodDetailView(source: source, initialMeal: meal)
                case .customEntry(let existingFood, let name, let brand, let barcode):
                    CustomFoodEditorView(
                        existingFood: existingFood,
                        prefilledName: name,
                        prefilledBrand: brand,
                        prefilledBarcode: barcode
                    )
                }
            }
            .task {
                if searchModel == nil {
                    searchModel = FoodSearchModel(dataSource: appEnvironment.foodDataSource)
                }
            }
        }
    }

    // MARK: - Search tab

    private var searchTab: some View {
        VStack(spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.Colors.secondaryText)
                TextField(
                    "Search foods",
                    text: Binding(
                        get: { searchModel?.query ?? "" },
                        set: { searchModel?.query = $0 }
                    )
                )
            }
            .padding(Theme.Spacing.sm)
            .background(Theme.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            .padding(.horizontal, Theme.Spacing.lg)

            Button {
                if let onScanRequested {
                    onScanRequested()
                } else {
                    showingScannerPlaceholder = true
                }
            } label: {
                Label("Scan Barcode", systemImage: "barcode.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding(.horizontal, Theme.Spacing.lg)
            .alert("Not Available Yet", isPresented: $showingScannerPlaceholder) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Barcode scanning is being built separately and will appear here.")
            }

            searchResultsList
        }
        .padding(.top, Theme.Spacing.sm)
    }

    @ViewBuilder
    private var searchResultsList: some View {
        switch searchModel?.phase ?? .idle {
        case .idle:
            ContentUnavailableView("Search for a Food", systemImage: "magnifyingglass")
        case .searching:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(Theme.Spacing.xl)
        case .loaded(let records):
            if records.isEmpty {
                ContentUnavailableView(
                    "No Results",
                    systemImage: "magnifyingglass",
                    description: Text("Try a different search, or enter it manually.")
                )
            } else {
                List(records) { record in
                    SearchResultRow(record: record)
                        .contentShape(Rectangle())
                        .onTapGesture { select(record) }
                }
                .listStyle(.plain)
            }
        case .failed(let error):
            FoodErrorView(error: error) { searchModel?.retry() }
        }
    }

    private func select(_ record: FoodRecord) {
        if record.lacksNutrition {
            destination = AddFoodDestination(kind: .customEntry(
                existingFood: nil,
                name: record.name,
                brand: record.brand,
                barcode: record.barcode
            ))
        } else {
            destination = AddFoodDestination(kind: .detail(.record(record)))
        }
    }

    // MARK: - My Foods tab

    private var myFoodsTab: some View {
        VStack(spacing: 0) {
            Button {
                destination = AddFoodDestination(kind: .customEntry(
                    existingFood: nil, name: "", brand: nil, barcode: nil
                ))
            } label: {
                Label("Create Custom Food", systemImage: "plus.circle")
            }
            .padding(Theme.Spacing.lg)

            foodList(myFoods, emptyTitle: "No custom foods yet", emptyIcon: "square.and.pencil")
        }
    }

    // MARK: - Shared food list (Recent / Frequent / My Foods)

    @ViewBuilder
    private func foodList(_ foods: [FoodItem], emptyTitle: String, emptyIcon: String) -> some View {
        if foods.isEmpty {
            ContentUnavailableView(emptyTitle, systemImage: emptyIcon)
        } else {
            List(foods) { food in
                FoodItemRow(food: food)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        destination = AddFoodDestination(kind: .detail(.existing(food)))
                    }
            }
            .listStyle(.plain)
        }
    }
}

// MARK: - Rows

private struct SearchResultRow: View {
    let record: FoodRecord

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(record.name)
                    if record.lacksNutrition {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(Theme.Colors.warning)
                    }
                }
                if let brand = record.brand {
                    Text(brand)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
                if record.lacksNutrition {
                    Text("No nutrition data — tap to enter manually")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.warning)
                }
            }
            Spacer()
            if !record.lacksNutrition {
                Text(Format.energy(record.nutrientsPer100g.effectiveKcal))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
        }
        .frame(minHeight: Theme.Layout.minimumTapTarget)
    }
}

private struct FoodItemRow: View {
    let food: FoodItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(food.displayTitle)
                Text("per 100 g: \(Format.energy(food.nutrientsPer100g.effectiveKcal))")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
            Spacer()
        }
        .frame(minHeight: Theme.Layout.minimumTapTarget)
    }
}

/// Shown in place of results when a lookup fails. The action offered depends
/// on ``FoodErrorAction`` rather than hard-coding a button per error case.
private struct FoodErrorView: View {
    let error: FoodDataError
    var onRetry: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: iconName)
                .font(.largeTitle)
                .foregroundStyle(Theme.Colors.secondaryText)
            Text(error.userMessage)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.Colors.secondaryText)
            if error.suggestedAction == .retry {
                Button("Retry", action: onRetry)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity)
    }

    private var iconName: String {
        switch error.suggestedAction {
        case .retry: "wifi.slash"
        case .manualEntry: "questionmark.circle"
        case .explainConfiguration: "key"
        }
    }
}

#Preview {
    AddFoodView(meal: .lunch)
        .modelContainer(TallySchema.previewContainer())
        .environment(\.appEnvironment, .preview())
}
