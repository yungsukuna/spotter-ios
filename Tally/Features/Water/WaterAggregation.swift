import Foundation

/// A logged drink's volume and day, decoupled from `WaterEntry` so the maths
/// below can be unit tested without standing up a `ModelContext`.
struct WaterRecord: Hashable, Sendable {
    var dayKey: String
    var volumeML: Double
}

extension WaterEntry {
    /// This entry as a storage-independent record, for use with ``WaterAggregation``.
    var record: WaterRecord { WaterRecord(dayKey: dayKey, volumeML: volumeML) }
}

/// Pure maths behind the Water screen: daily totals, goal progress, and the
/// 7-day history series.
///
/// Kept free of SwiftUI and SwiftData so it can be unit tested directly,
/// mirroring how `StrengthMath` is factored out of the workout views.
enum WaterAggregation {

    /// Sum of volumes across the given records, in millilitres.
    static func totalML(_ records: [WaterRecord]) -> Double {
        records.reduce(0) { $0 + $1.volumeML }
    }

    /// Fraction of the daily goal reached, e.g. `0.4` for 40%.
    ///
    /// Deliberately not clamped to `0...1` — a ring view clamps its own fill,
    /// but a "127%" label needs the true value, and a goal of zero (never
    /// configured) must not divide by zero.
    static func progressFraction(totalML: Double, goalML: Double) -> Double {
        guard goalML > 0 else { return 0 }
        return totalML / goalML
    }

    /// One day's total against the goal, for the history chart.
    struct DayTotal: Hashable, Identifiable, Sendable {
        var dayKey: String
        var totalML: Double
        var goalML: Double
        var id: String { dayKey }
    }

    /// Builds one `DayTotal` per key in `keys`, in the order given.
    ///
    /// A day with no logged entries still appears, at zero — dropping it
    /// would make the chart's x-axis silently skip days rather than show an
    /// honest zero, which is the whole point of a streak chart.
    static func dailyTotals(records: [WaterRecord], keys: [String], goalML: Double) -> [DayTotal] {
        let grouped = Dictionary(grouping: records, by: \.dayKey)
        return keys.map { key in
            DayTotal(dayKey: key, totalML: totalML(grouped[key] ?? []), goalML: goalML)
        }
    }
}
