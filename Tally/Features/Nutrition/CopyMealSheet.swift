import SwiftData
import SwiftUI

/// Copy another day's entries for one meal into the day currently open in
/// the diary.
///
/// `targetDayKey` is the day being *viewed*, not necessarily today — see the
/// note on `NutritionDiaryView`. The source day and meal default to
/// yesterday and the meal that was tapped, but can be changed before adding.
struct CopyMealSheet: View {
    let targetDayKey: String
    let targetMeal: Meal

    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @Environment(\.dismiss) private var dismiss

    @State private var sourceDate: Date
    @State private var sourceMeal: Meal
    @State private var sourceEntries: [DiaryEntry] = []
    @State private var selectedIDs: Set<UUID> = []

    init(targetDayKey: String, targetMeal: Meal, initialSourceDate: Date = Date()) {
        self.targetDayKey = targetDayKey
        self.targetMeal = targetMeal
        _sourceDate = State(initialValue: initialSourceDate)
        _sourceMeal = State(initialValue: targetMeal)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $sourceDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                }

                Section("Meal") {
                    Picker("Meal", selection: $sourceMeal) {
                        ForEach(Meal.ordered) { meal in
                            Text(meal.displayName).tag(meal)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    if sourceEntries.isEmpty {
                        Text("No entries logged that day.")
                            .foregroundStyle(Theme.Colors.secondaryText)
                    } else {
                        ForEach(sourceEntries) { entry in
                            sourceEntryRow(entry)
                        }
                    }
                }
            }
            .navigationTitle("Copy Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add \(selectedIDs.count) Item\(selectedIDs.count == 1 ? "" : "s")") {
                        addSelected()
                    }
                    .disabled(selectedIDs.isEmpty)
                }
            }
            .onChange(of: sourceDate) { _, _ in reloadSourceEntries() }
            .onChange(of: sourceMeal) { _, _ in reloadSourceEntries() }
            .task { reloadSourceEntries() }
        }
    }

    private func sourceEntryRow(_ entry: DiaryEntry) -> some View {
        let isSelected = selectedIDs.contains(entry.id)
        return Button {
            toggle(entry.id)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(entry.foodName)
                        .foregroundStyle(Theme.Colors.primaryText)
                    Text(entry.portionDescription)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Theme.Colors.accent : Theme.Colors.secondaryText)
            }
            .frame(minHeight: Theme.Layout.minimumTapTarget)
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private func reloadSourceEntries() {
        let key = DayKey.make(from: sourceDate, calendar: calendar)
        let descriptor = FetchDescriptor<DiaryEntry>(
            predicate: #Predicate<DiaryEntry> { $0.dayKey == key },
            sortBy: [SortDescriptor(\.loggedAt)]
        )
        let fetched = (try? modelContext.fetch(descriptor)) ?? []
        sourceEntries = fetched.filter { $0.meal == sourceMeal }
        selectedIDs = Set(sourceEntries.map(\.id))
    }

    private func addSelected() {
        let snapshots = sourceEntries
            .filter { selectedIDs.contains($0.id) }
            .map(DiaryEntrySnapshot.init(entry:))
        let newEntries = MealCopy.copies(
            of: snapshots,
            into: targetMeal,
            dayKey: targetDayKey,
            now: Date(),
            calendar: calendar
        )
        for entry in newEntries {
            modelContext.insert(entry)
        }
        WidgetSnapshotWriter.refresh(in: modelContext)
        dismiss()
    }
}

#Preview {
    CopyMealSheet(targetDayKey: Date().dayKey, targetMeal: .breakfast)
        .modelContainer(TallySchema.previewContainer())
        .environment(\.appEnvironment, .preview())
}
