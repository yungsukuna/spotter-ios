import SwiftData
import SwiftUI

/// Root of the Water tab.
///
/// Shows today's progress against the goal as a fill ring, quick-add presets
/// from `UserSettings.waterPresets`, the day's logged entries, and a 7-day
/// history chart. `selectedDate` drives which day is shown; the day's content
/// is rebuilt (via `.id(dayKey)`) whenever it changes, which is what lets a
/// `@Query` filtered on a single `dayKey` follow date navigation.
struct WaterView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsList: [UserSettings]

    @State private var selectedDate = Date()

    private let calendar = Calendar.current

    private var settings: UserSettings {
        settingsList.first ?? UserSettings.current(in: modelContext)
    }

    private var dayKey: String { DayKey.make(from: selectedDate, calendar: calendar) }
    private var isToday: Bool { calendar.isDateInToday(selectedDate) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                WaterDateNavigationBar(date: $selectedDate, calendar: calendar)
                WaterDayScreen(dayKey: dayKey, isToday: isToday, settings: settings)
                    .id(dayKey)
            }
            .navigationTitle("Water")
        }
    }
}

/// Prev/next day controls. "Next" is disabled once the selected day is today
/// — logging ahead of time makes no sense.
private struct WaterDateNavigationBar: View {
    @Binding var date: Date
    let calendar: Calendar

    private var isToday: Bool { calendar.isDateInToday(date) }

    var body: some View {
        HStack {
            Button {
                move(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .frame(width: Theme.Layout.minimumTapTarget, height: Theme.Layout.minimumTapTarget)

            Spacer()

            Text(date, format: .dateTime.weekday(.wide).month().day())
                .font(Theme.Typography.cardTitle)

            Spacer()

            Button {
                move(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .frame(width: Theme.Layout.minimumTapTarget, height: Theme.Layout.minimumTapTarget)
            .disabled(isToday)
        }
        .padding(.horizontal, Theme.Spacing.sm)
    }

    private func move(by dayDelta: Int) {
        guard let newDate = calendar.date(byAdding: .day, value: dayDelta, to: date) else { return }
        date = newDate
    }
}

/// The scrollable content for one day: progress ring, quick add (today only),
/// the entry list, and the history chart.
private struct WaterDayScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var entries: [WaterEntry]

    let dayKey: String
    let isToday: Bool
    let settings: UserSettings

    @State private var showingCustomSheet = false
    @State private var recentlyAdded: WaterEntry?

    init(dayKey: String, isToday: Bool, settings: UserSettings) {
        self.dayKey = dayKey
        self.isToday = isToday
        self.settings = settings
        _entries = Query(
            filter: #Predicate<WaterEntry> { $0.dayKey == dayKey },
            sort: \WaterEntry.loggedAt,
            order: .reverse
        )
    }

    private var totalML: Double {
        WaterAggregation.totalML(entries.map(\.record))
    }

    var body: some View {
        List {
            Section {
                progressHeader
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if isToday {
                Section("Quick add") {
                    quickAddGrid
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section(isToday ? "Today" : "Entries") {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "No water logged",
                        systemImage: "drop",
                        description: Text(isToday ? "Use a quick-add button below to get started." : "Nothing was logged this day.")
                    )
                } else {
                    ForEach(entries) { entry in
                        WaterEntryRow(entry: entry, unit: settings.volumeUnit)
                    }
                    .onDelete(perform: deleteEntries)
                }
            }

            Section("Last 7 days") {
                WaterHistoryChart(goalML: settings.dailyWaterGoalML, unit: settings.volumeUnit)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
        .overlay(alignment: .bottom) { undoBanner }
        .animation(.default, value: recentlyAdded != nil)
        .sheet(isPresented: $showingCustomSheet) {
            WaterCustomAmountSheet(unit: settings.volumeUnit) { volumeML in
                addEntry(volumeML: volumeML, presetLabel: nil)
            }
        }
        .task(id: recentlyAdded?.id) {
            guard recentlyAdded != nil else { return }
            try? await Task.sleep(for: .seconds(4))
            recentlyAdded = nil
        }
    }

    private var progressHeader: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ZStack {
                WaterProgressRing(fraction: WaterAggregation.progressFraction(totalML: totalML, goalML: settings.dailyWaterGoalML))
                    .frame(width: 160, height: 160)
                VStack(spacing: Theme.Spacing.xxs) {
                    Text(Format.volume(totalML, in: settings.volumeUnit))
                        .font(Theme.Typography.metric)
                    Text("of \(Format.volume(settings.dailyWaterGoalML, in: settings.volumeUnit)) goal")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.sm)
    }

    private var quickAddGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: Theme.Spacing.sm)], spacing: Theme.Spacing.sm) {
            ForEach(settings.waterPresets) { preset in
                Button {
                    addEntry(volumeML: preset.volumeML, presetLabel: preset.label)
                } label: {
                    VStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: preset.symbolName)
                            .font(.title2)
                        Text(preset.label)
                            .font(.caption)
                        Text(Format.volume(preset.volumeML, in: settings.volumeUnit))
                            .font(.caption2)
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                    .frame(maxWidth: .infinity, minHeight: Theme.Layout.minimumTapTarget)
                    .padding(Theme.Spacing.sm)
                    .background(Theme.Colors.water.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Button {
                showingCustomSheet = true
            } label: {
                VStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "plus.circle")
                        .font(.title2)
                    Text("Custom")
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, minHeight: Theme.Layout.minimumTapTarget)
                .padding(Theme.Spacing.sm)
                .background(Theme.Colors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var undoBanner: some View {
        if let recentlyAdded {
            HStack {
                Text("Added \(Format.volume(recentlyAdded.volumeML, in: settings.volumeUnit))")
                    .font(Theme.Typography.caption)
                Spacer()
                Button("Undo") { undoRecentlyAdded() }
                    .font(Theme.Typography.caption.weight(.semibold))
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            .shadow(radius: 4)
            .padding(Theme.Spacing.md)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func addEntry(volumeML: Double, presetLabel: String?) {
        let entry = WaterEntry(volumeML: volumeML, presetLabel: presetLabel, calendar: calendar)
        modelContext.insert(entry)
        recentlyAdded = entry
    }

    private func deleteEntries(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(entries[index])
        }
    }

    private func undoRecentlyAdded() {
        guard let recentlyAdded else { return }
        modelContext.delete(recentlyAdded)
        self.recentlyAdded = nil
    }

    private var calendar: Calendar { .current }
}

#Preview {
    WaterView()
        .modelContainer(TallySchema.previewContainer())
        .environment(\.appEnvironment, .preview())
}
