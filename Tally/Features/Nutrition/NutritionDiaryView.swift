import SwiftData
import SwiftUI

/// Root of the Food tab: one day's diary, grouped by meal.
///
/// Owned by workstream A.
///
/// The day being viewed lives here; the entries for it live in
/// ``DiaryDayContent`` below, given to it as a `dayKey` rather than a `Date`.
/// `DiaryDayContent` is tagged `.id(dayKey)` so that changing the day forces
/// SwiftUI to rebuild it — and with it, the `@Query` — rather than trying to
/// mutate a `@Query`'s predicate in place, which SwiftData does not support.
struct NutritionDiaryView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var selectedDate = Date()
    @State private var settings: UserSettings?
    @State private var showingGoals = false

    private var dayKey: String { selectedDate.dayKey }

    /// Falls back to ``UserSettings``' own defaults before the singleton row
    /// has loaded, so the totals card never flashes a zero goal on first
    /// appearance.
    private var goal: Nutrients {
        settings?.nutritionGoal ?? Nutrients(kcal: 2000, proteinG: 150, carbsG: 200, fatG: 67)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DiaryDateHeader(date: $selectedDate)
                Divider()
                DiaryDayContent(dayKey: dayKey, goal: goal)
                    .id(dayKey)
            }
            .navigationTitle("Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingGoals = true
                    } label: {
                        Image(systemName: "target")
                    }
                    .accessibilityLabel("Edit Goals")
                }
            }
            .sheet(isPresented: $showingGoals) {
                GoalsEditorView()
            }
            .task {
                if settings == nil {
                    settings = UserSettings.current(in: modelContext)
                }
            }
        }
    }
}

/// Prev/next day navigation, with a way back to today.
private struct DiaryDateHeader: View {
    @Binding var date: Date
    @Environment(\.calendar) private var calendar

    private var isToday: Bool { calendar.isDateInToday(date) }

    private var title: String {
        if isToday { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    var body: some View {
        HStack {
            Button {
                step(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .frame(minWidth: Theme.Layout.minimumTapTarget, minHeight: Theme.Layout.minimumTapTarget)

            Spacer()

            VStack(spacing: Theme.Spacing.xxs) {
                Text(title).font(Theme.Typography.cardTitle)
                if !isToday {
                    Button("Today") { date = Date() }
                        .font(Theme.Typography.caption)
                }
            }

            Spacer()

            Button {
                step(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .frame(minWidth: Theme.Layout.minimumTapTarget, minHeight: Theme.Layout.minimumTapTarget)
        }
        .padding(.horizontal, Theme.Spacing.lg)
    }

    private func step(by days: Int) {
        if let newDate = calendar.date(byAdding: .day, value: days, to: date) {
            date = newDate
        }
    }
}

/// The list content for one day: totals card, then a section per meal.
///
/// Takes `dayKey` as a plain `String` rather than deriving it from a `Date`
/// itself, so the `#Predicate` built in `init` always matches exactly what
/// the parent intended — see the note on ``NutritionDiaryView``.
private struct DiaryDayContent: View {
    let dayKey: String
    let goal: Nutrients

    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @Query private var entries: [DiaryEntry]

    @State private var addFoodMeal: Meal?
    @State private var quickAddMeal: Meal?
    @State private var copyMealTarget: Meal?
    @State private var editingEntry: DiaryEntry?
    @State private var savingMeal: Meal?
    @State private var savedMealName = ""

    init(dayKey: String, goal: Nutrients) {
        self.dayKey = dayKey
        self.goal = goal
        _entries = Query(
            filter: #Predicate<DiaryEntry> { $0.dayKey == dayKey },
            sort: [SortDescriptor(\DiaryEntry.loggedAt)]
        )
    }

    private var totals: DayTotals { DayTotals(entries: entries, goal: goal) }

    private func rows(for meal: Meal) -> [DiaryEntry] {
        entries.filter { $0.meal == meal }
    }

    var body: some View {
        List {
            Section {
                DayTotalsCard(totals: totals, hasEntries: !entries.isEmpty)
                    .tallyCard()
            }
            .listRowBackground(Color.clear)

            ForEach(Meal.ordered) { meal in
                let mealEntries = rows(for: meal)
                Section {
                    ForEach(mealEntries) { entry in
                        DiaryEntryRow(entry: entry)
                            .contentShape(Rectangle())
                            .onTapGesture { editingEntry = entry }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    modelContext.delete(entry)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                    Button {
                        addFoodMeal = meal
                    } label: {
                        Label("Add Food", systemImage: "plus.circle")
                    }
                    Button {
                        quickAddMeal = meal
                    } label: {
                        Label("Quick Add", systemImage: "bolt")
                    }
                } header: {
                    MealSectionHeader(
                        meal: meal,
                        onCopyYesterday: { copyFromYesterday(into: meal) },
                        onCopyFrom: { copyMealTarget = meal },
                        onSaveAsMeal: {
                            savedMealName = ""
                            savingMeal = meal
                        }
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
        .sheet(item: $addFoodMeal) { meal in
            AddFoodView(meal: meal)
        }
        .sheet(item: $quickAddMeal) { meal in
            QuickAddSheet(meal: meal)
        }
        .sheet(item: $copyMealTarget) { meal in
            CopyMealSheet(
                targetDayKey: dayKey,
                targetMeal: meal,
                initialSourceDate: previousDay
            )
        }
        .sheet(
            isPresented: Binding(
                get: { editingEntry != nil },
                set: { isPresented in if !isPresented { editingEntry = nil } }
            )
        ) {
            if let editingEntry {
                EditDiaryEntryView(entry: editingEntry)
            }
        }
        .alert(
            "Save as Meal",
            isPresented: Binding(
                get: { savingMeal != nil },
                set: { isPresented in if !isPresented { savingMeal = nil } }
            ),
            presenting: savingMeal
        ) { meal in
            TextField("Name", text: $savedMealName)
            Button("Save") { saveAsMeal(meal) }
            Button("Cancel", role: .cancel) {}
        } message: { meal in
            let count = rows(for: meal).count
            Text("Saves \(count) item\(count == 1 ? "" : "s") from \(meal.displayName).")
        }
    }

    /// The day before the one being viewed, used as the default source date
    /// when "Copy from…" opens.
    private var previousDay: Date {
        guard let dayStart = DayKey.date(from: dayKey, calendar: calendar) else { return Date() }
        return calendar.date(byAdding: .day, value: -1, to: dayStart) ?? dayStart
    }

    private func copyFromYesterday(into meal: Meal) {
        guard let dayStart = DayKey.date(from: dayKey, calendar: calendar),
              let yesterday = calendar.date(byAdding: .day, value: -1, to: dayStart)
        else { return }
        let yesterdayKey = DayKey.make(from: yesterday, calendar: calendar)
        let descriptor = FetchDescriptor<DiaryEntry>(
            predicate: #Predicate<DiaryEntry> { $0.dayKey == yesterdayKey },
            sortBy: [SortDescriptor(\.loggedAt)]
        )
        let fetched = (try? modelContext.fetch(descriptor)) ?? []
        let snapshots = fetched.filter { $0.meal == meal }.map(DiaryEntrySnapshot.init(entry:))
        guard !snapshots.isEmpty else { return }
        let newEntries = MealCopy.copies(of: snapshots, into: meal, dayKey: dayKey, now: Date(), calendar: calendar)
        for entry in newEntries {
            modelContext.insert(entry)
        }
    }

    private func saveAsMeal(_ meal: Meal) {
        let trimmedName = savedMealName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let snapshots = rows(for: meal).map(DiaryEntrySnapshot.init(entry:))
        guard !snapshots.isEmpty else { return }
        let items = SavedMealLogging.items(from: snapshots)
        let savedMeal = SavedMeal(name: trimmedName, defaultMeal: meal, items: items)
        modelContext.insert(savedMeal)
    }
}

/// Meal section header: the meal name, plus a menu for copying entries in or
/// saving the section as a reusable meal.
private struct MealSectionHeader: View {
    let meal: Meal
    var onCopyYesterday: () -> Void
    var onCopyFrom: () -> Void
    var onSaveAsMeal: () -> Void

    var body: some View {
        HStack {
            Label(meal.displayName, systemImage: meal.symbolName)
            Spacer()
            Menu {
                Button("Copy from Yesterday", action: onCopyYesterday)
                Button("Copy from…", action: onCopyFrom)
                Button("Save as Meal", action: onSaveAsMeal)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .frame(minWidth: Theme.Layout.minimumTapTarget, minHeight: Theme.Layout.minimumTapTarget)
        }
    }
}

/// Calories against goal, plus the three macros. Doubles as the diary's empty
/// state: with nothing logged yet, a short note replaces the "remaining"
/// figure rather than showing a full-screen placeholder that would hide the
/// per-meal "Add Food" rows underneath — those rows are how you add the first
/// entry, so they need to stay visible even on an empty day.
private struct DayTotalsCard: View {
    let totals: DayTotals
    let hasEntries: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(Format.energy(totals.consumed.effectiveKcal))
                        .font(Theme.Typography.metric)
                    Text("of \(Format.energy(totals.goal.kcal)) goal")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
                Spacer()
                if let remaining = totals.kcalRemaining {
                    VStack(alignment: .trailing, spacing: Theme.Spacing.xxs) {
                        Text(Format.energy(abs(remaining), includeUnit: false))
                            .font(Theme.Typography.metricSmall)
                        Text(remaining >= 0 ? "remaining" : "over")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                }
            }

            ProgressView(value: totals.kcalProgress)
                .tint(Theme.Colors.nutrition)

            HStack(spacing: Theme.Spacing.lg) {
                MacroBadge(label: "Protein", value: totals.consumed.proteinG, color: Theme.Colors.protein)
                MacroBadge(label: "Carbs", value: totals.consumed.carbsG, color: Theme.Colors.carbs)
                MacroBadge(label: "Fat", value: totals.consumed.fatG, color: Theme.Colors.fat)
            }

            if !hasEntries {
                Text("No food logged yet today.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
        }
    }
}

private struct MacroBadge: View {
    let label: String
    let value: Double?
    let color: Color

    var body: some View {
        VStack(spacing: Theme.Spacing.xxs) {
            Text(Format.grams(value, includeUnit: false))
                .font(Theme.Typography.metricSmall)
                .foregroundStyle(color)
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct DiaryEntryRow: View {
    let entry: DiaryEntry

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(entry.foodName)
                Text(entry.portionDescription)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
            Spacer()
            Text(Format.energy(entry.nutrients.kcal))
                .font(Theme.Typography.setValue)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
        .frame(minHeight: Theme.Layout.minimumTapTarget)
    }
}

#Preview {
    NutritionDiaryView()
        .modelContainer(TallySchema.previewContainer())
        .environment(\.appEnvironment, .preview())
}
