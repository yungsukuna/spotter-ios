import Foundation
import SwiftData

/// Turns raw weigh-ins into a smoothed trend, the way the Hacker's Diet does:
/// a daily mean (multiple weigh-ins on one day are noise, not signal), then a
/// time-aware exponential moving average so a gap in logging doesn't distort
/// the curve.
///
/// Pure and container-free by design — `BodyWeightCard`, `BodyWeightView`,
/// the goal calculator and the cardio calorie estimate all want "today's
/// trend weight" without pulling in a view. The one `ModelContext`-aware
/// entry point is `latestTrendKG(in:)`, which is just a fetch plus a call
/// into the pure functions below.
enum BodyWeightTrend {

    /// One recorded weigh-in, reduced to what the maths needs. `BodyMeasurement`
    /// already carries both fields; this decouples the logic from SwiftData so
    /// tests need no container.
    struct WeighIn: Sendable {
        var dayKey: String
        var kg: Double
    }

    /// One day's trend value, alongside that day's raw (mean) weigh-in for the
    /// chart's scatter layer.
    struct TrendPoint: Identifiable, Hashable, Sendable {
        var dayKey: String
        var raw: Double
        var trend: Double
        var id: String { dayKey }
    }

    /// Collapses same-day weigh-ins to their mean, per Decision 8. Sorted
    /// ascending by day key, which sorts chronologically since keys are
    /// zero-padded `yyyy-MM-dd`.
    static func dailyMeans(_ weighIns: [WeighIn]) -> [(dayKey: String, kg: Double)] {
        let grouped = Dictionary(grouping: weighIns, by: \.dayKey)
        return grouped
            .map { dayKey, values in
                (dayKey: dayKey, kg: values.reduce(0) { $0 + $1.kg } / Double(values.count))
            }
            .sorted { $0.dayKey < $1.dayKey }
    }

    /// A time-aware EWMA over daily means, alpha = 0.1/day by default.
    ///
    /// The trend is seeded with the first value, then walked forward. A gap of
    /// `n` calendar days (via `DayKey.date(from:)` and
    /// `calendar.dateComponents([.day])`, never 86_400-second arithmetic, so a
    /// daylight-saving transition can't shift the count) uses an effective
    /// alpha of `1 − (1 − alpha)^n`, which is mathematically identical to
    /// applying the single-day step `n` times in a row.
    static func trend(
        _ dailyMeans: [(dayKey: String, kg: Double)],
        alpha: Double = 0.1,
        calendar: Calendar = .current
    ) -> [TrendPoint] {
        guard let first = dailyMeans.first else { return [] }

        var points: [TrendPoint] = [TrendPoint(dayKey: first.dayKey, raw: first.kg, trend: first.kg)]
        var previousTrend = first.kg
        var previousDate = DayKey.date(from: first.dayKey, calendar: calendar)

        for entry in dailyMeans.dropFirst() {
            let currentDate = DayKey.date(from: entry.dayKey, calendar: calendar)
            let daysGap: Int = {
                guard let previousDate, let currentDate else { return 1 }
                let day = calendar.dateComponents([.day], from: previousDate, to: currentDate).day ?? 1
                return max(1, day)
            }()

            let effectiveAlpha = 1 - pow(1 - alpha, Double(daysGap))
            let newTrend = previousTrend + effectiveAlpha * (entry.kg - previousTrend)

            points.append(TrendPoint(dayKey: entry.dayKey, raw: entry.kg, trend: newTrend))
            previousTrend = newTrend
            previousDate = currentDate
        }

        return points
    }

    /// The change in trend weight over the most recent week: the latest point
    /// minus the trend at or before (latest day − 7 days). Nil when there is
    /// under a week of history to compare against.
    static func weeklyRate(_ points: [TrendPoint], calendar: Calendar = .current) -> Double? {
        guard
            let latest = points.last,
            let latestDate = DayKey.date(from: latest.dayKey, calendar: calendar),
            let weekAgo = calendar.date(byAdding: .day, value: -7, to: latestDate)
        else { return nil }

        let reference = points.last { point in
            guard let date = DayKey.date(from: point.dayKey, calendar: calendar) else { return false }
            return date <= weekAgo
        }
        guard let reference else { return nil }

        return latest.trend - reference.trend
    }

    /// The most recent trend value, or nil with no weigh-ins.
    static func latestTrendKG(from weighIns: [WeighIn], calendar: Calendar = .current) -> Double? {
        trend(dailyMeans(weighIns), calendar: calendar).last?.trend
    }

    /// Fetches every `BodyMeasurement` of type `.bodyWeight` from `context` and
    /// returns the latest trend weight in kilograms. Used by the goal
    /// calculator and the cardio calorie estimate, which both need "current
    /// weight" without owning a chart or a query of their own.
    @MainActor
    static func latestTrendKG(in context: ModelContext) -> Double? {
        let bodyWeightRaw = MeasurementType.bodyWeight.rawValue
        let descriptor = FetchDescriptor<BodyMeasurement>(
            predicate: #Predicate<BodyMeasurement> { $0.typeRaw == bodyWeightRaw }
        )
        guard let rows = try? context.fetch(descriptor) else { return nil }

        let weighIns = rows.map { WeighIn(dayKey: $0.dayKey, kg: $0.value) }
        return latestTrendKG(from: weighIns)
    }
}
