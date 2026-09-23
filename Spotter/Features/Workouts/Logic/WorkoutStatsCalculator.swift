import Foundation

/// Aggregates one exercise's history into the series the stats screen charts,
/// plus the rep-record table.
///
/// All the actual maths (1RM estimate, volume, PR comparison) lives in
/// `StrengthMath` and is not repeated here — this type is only responsible
/// for pulling the right sets out of the object graph, filtering by date
/// range, and collapsing a session's several sets into one chart point.
enum WorkoutStatsCalculator {

    /// A selectable window for the stats screen's charts.
    enum DateRange: String, CaseIterable, Identifiable, Sendable {
        case oneMonth, threeMonths, sixMonths, oneYear, allTime

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .oneMonth: "1M"
            case .threeMonths: "3M"
            case .sixMonths: "6M"
            case .oneYear: "1Y"
            case .allTime: "All"
            }
        }

        /// The earliest date to include, or nil for no lower bound.
        func cutoff(from now: Date = Date(), calendar: Calendar = .current) -> Date? {
            switch self {
            case .oneMonth: calendar.date(byAdding: .month, value: -1, to: now)
            case .threeMonths: calendar.date(byAdding: .month, value: -3, to: now)
            case .sixMonths: calendar.date(byAdding: .month, value: -6, to: now)
            case .oneYear: calendar.date(byAdding: .year, value: -1, to: now)
            case .allTime: nil
            }
        }
    }

    /// One point on a chart: a date and a value, whatever the value means for
    /// that particular series.
    struct DataPoint: Identifiable, Hashable, Sendable {
        var date: Date
        var value: Double
        var id: Date { date }
    }

    /// Every completed working set for `exercise`, oldest first, within
    /// `range`. Warm-ups are excluded, matching `StrengthMath`'s treatment of
    /// them everywhere else.
    static func completedSets(
        for exercise: Exercise,
        range: DateRange = .allTime,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [StrengthMath.CompletedSet] {
        let cutoff = range.cutoff(from: now, calendar: calendar)
        return exercise.workoutEntries
            .flatMap(\.orderedSets)
            .filter { !$0.isWarmup }
            .compactMap(\.completedSetValue)
            .filter { cutoff == nil || $0.performedAt >= cutoff! }
            .sorted { $0.performedAt < $1.performedAt }
    }

    /// One point per session: the best estimated 1RM logged that day.
    static func oneRepMaxSeries(
        for exercise: Exercise,
        formula: OneRepMaxFormula = .epley,
        range: DateRange = .allTime
    ) -> [DataPoint] {
        groupedByDay(completedSets(for: exercise, range: range)) { sets in
            sets.compactMap { $0.estimatedOneRepMax(formula: formula) }.max()
        }
    }

    /// One point per session: total tonnage that day.
    static func volumeSeries(for exercise: Exercise, range: DateRange = .allTime) -> [DataPoint] {
        groupedByDay(completedSets(for: exercise, range: range)) { sets in
            sets.reduce(0) { $0 + $1.volumeKG }
        }
    }

    /// One point per session: the heaviest completed weight that day.
    static func heaviestWeightSeries(for exercise: Exercise, range: DateRange = .allTime) -> [DataPoint] {
        groupedByDay(completedSets(for: exercise, range: range)) { sets in
            sets.map(\.weightKG).max()
        }
    }

    /// The rep-record table: best weight ever lifted per rep count, across
    /// all history regardless of the selected chart range.
    static func repRecords(for exercise: Exercise) -> [StrengthMath.RepRecord] {
        StrengthMath.repRecords(from: completedSets(for: exercise, range: .allTime))
    }

    /// Group sets by calendar day — several sets in one session collapse to a
    /// single chart point — and reduce each day with `reducer`. Days where the
    /// reducer returns nil (e.g. an all-bodyweight day with no estimable 1RM)
    /// are dropped rather than plotted as zero.
    private static func groupedByDay(
        _ sets: [StrengthMath.CompletedSet],
        reducer: ([StrengthMath.CompletedSet]) -> Double?
    ) -> [DataPoint] {
        let grouped = Dictionary(grouping: sets) { DayKey.make(from: $0.performedAt) }
        return grouped
            .compactMap { _, daySets -> DataPoint? in
                guard let value = reducer(daySets), let date = daySets.map(\.performedAt).min() else {
                    return nil
                }
                return DataPoint(date: date, value: value)
            }
            .sorted { $0.date < $1.date }
    }
}
