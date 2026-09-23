import SwiftUI
import WidgetKit

/// Home Screen / Lock Screen widget showing kcal and water remaining today.
///
/// Reads whatever ``WidgetSnapshot`` the app last wrote to the App Group's
/// shared `UserDefaults` (Decision 12 — a snapshot, not a live read of the
/// SwiftData store). This target links nothing from the app beyond `Theme`,
/// `UnitConverter`/`Format`, `DayKey` and `Enums.swift` — no SwiftData, no
/// app models.
struct DailyRemainingProvider: TimelineProvider {
    func placeholder(in context: Context) -> DailyRemainingEntry {
        DailyRemainingEntry(date: Date(), snapshot: Self.placeholderSnapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (DailyRemainingEntry) -> Void) {
        let snapshot = WidgetSnapshotStore.load() ?? Self.placeholderSnapshot
        completion(DailyRemainingEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DailyRemainingEntry>) -> Void) {
        let now = Date()
        let calendar = Calendar.current
        let snapshot = WidgetSnapshotStore.load()

        let entries = [DailyRemainingEntry(date: now, snapshot: snapshot)]

        // Refresh again at the next local midnight, so the stale-day rule in
        // `WidgetSnapshot.displayValues(today:)` flips the display to zero
        // right when the day rolls over, not whenever iOS next happens to
        // reload the widget.
        if let nextMidnight = calendar.nextDate(
            after: now,
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) {
            completion(Timeline(entries: entries, policy: .after(nextMidnight)))
        } else {
            completion(Timeline(entries: entries, policy: .atEnd))
        }
    }

    /// A snapshot shown when the app has never written one yet (fresh
    /// install), rendered as a placeholder rather than real numbers.
    static let placeholderSnapshot = WidgetSnapshot(
        dayKey: DayKey.today(),
        kcalConsumed: nil,
        kcalGoal: 2000,
        waterML: 0,
        waterGoalML: 2500,
        volumeUnitRaw: VolumeUnit.millilitres.rawValue,
        generatedAt: Date()
    )
}

struct DailyRemainingEntry: TimelineEntry {
    var date: Date
    /// `nil` when no snapshot has ever been written — the app has never
    /// launched with the App Group entitlement active, or the suite is
    /// unavailable. Rendered as a placeholder.
    var snapshot: WidgetSnapshot?
}

struct DailyRemainingWidgetEntryView: View {
    var entry: DailyRemainingEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let snapshot = entry.snapshot {
            let display = snapshot.displayValues(today: DayKey.today())
            content(for: display)
        } else {
            placeholderContent
        }
    }

    @ViewBuilder
    private func content(for snapshot: WidgetSnapshot) -> some View {
        switch family {
        case .accessoryCircular:
            circular(snapshot)
        case .accessoryRectangular:
            rectangular(snapshot)
        case .systemMedium:
            medium(snapshot)
        default:
            small(snapshot)
        }
    }

    private var placeholderContent: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text("Spotter")
                .font(Theme.Typography.cardTitle)
            Text("Open the app to start tracking")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.Spacing.md)
        .containerBackground(for: .widget) { Theme.Colors.groupedBackground }
    }

    private func kcalRemaining(_ snapshot: WidgetSnapshot) -> Double {
        max(0, snapshot.kcalGoal - (snapshot.kcalConsumed ?? 0))
    }

    private func waterRemainingML(_ snapshot: WidgetSnapshot) -> Double {
        max(0, snapshot.waterGoalML - snapshot.waterML)
    }

    private var volumeUnit: VolumeUnit {
        VolumeUnit(rawValue: (entry.snapshot?.volumeUnitRaw) ?? VolumeUnit.millilitres.rawValue) ?? .millilitres
    }

    private func small(_ snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Image(systemName: "flame.fill")
                .foregroundStyle(Theme.Colors.nutrition)
            Text(Format.energy(kcalRemaining(snapshot), includeUnit: false))
                .font(Theme.Typography.metricSmall)
            Text("kcal left")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .containerBackground(for: .widget) { Theme.Colors.groupedBackground }
    }

    private func medium(_ snapshot: WidgetSnapshot) -> some View {
        HStack(spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Label("Calories", systemImage: "flame.fill")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.nutrition)
                Text(Format.energy(kcalRemaining(snapshot), includeUnit: false))
                    .font(Theme.Typography.metricSmall)
                Text("of \(Format.energy(snapshot.kcalGoal))")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Label("Water", systemImage: "drop.fill")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.water)
                Text(Format.volume(waterRemainingML(snapshot), in: volumeUnit))
                    .font(Theme.Typography.metricSmall)
                Text("of \(Format.volume(snapshot.waterGoalML, in: volumeUnit))")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Theme.Spacing.md)
        .containerBackground(for: .widget) { Theme.Colors.groupedBackground }
    }

    private func rectangular(_ snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text("\(Format.energy(kcalRemaining(snapshot), includeUnit: false)) kcal left")
                .font(Theme.Typography.caption)
            Text("\(Format.volume(waterRemainingML(snapshot), in: volumeUnit)) water left")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    private func circular(_ snapshot: WidgetSnapshot) -> some View {
        let fraction = snapshot.kcalGoal > 0
            ? min(1, max(0, (snapshot.kcalConsumed ?? 0) / snapshot.kcalGoal))
            : 0
        return Gauge(value: fraction) {
            Image(systemName: "flame.fill")
        } currentValueLabel: {
            Text(Format.energy(kcalRemaining(snapshot), includeUnit: false))
                .font(Theme.Typography.caption)
        }
        .gaugeStyle(.accessoryCircular)
        .containerBackground(for: .widget) { Color.clear }
    }
}

struct DailyRemainingWidget: Widget {
    private let kind = "DailyRemainingWidget"

    init() {}

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DailyRemainingProvider()) { entry in
            DailyRemainingWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Today's Remaining")
        .description("Calories and water left for today.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }
}

#Preview(as: .systemSmall) {
    DailyRemainingWidget()
} timeline: {
    DailyRemainingEntry(date: Date(), snapshot: DailyRemainingProvider.placeholderSnapshot)
}
