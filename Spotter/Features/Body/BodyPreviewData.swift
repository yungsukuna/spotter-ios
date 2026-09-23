import Foundation
import SwiftData

/// Seed data for Body feature previews.
///
/// Not used by the app itself — every `#Preview` in this feature calls into
/// here so previews show a realistic, trending-down history instead of an
/// empty screen, per the house style described in `CLAUDE.md`.
enum BodyPreviewData {

    /// Ten weigh-ins over about two months, trending gently downward, spaced
    /// unevenly to exercise the gap-aware trend.
    private static let sampleOffsetsAndWeights: [(daysAgo: Int, kg: Double)] = [
        (60, 84.2), (52, 83.6), (45, 83.9), (38, 83.1), (31, 82.8),
        (24, 82.6), (17, 82.1), (10, 81.7), (5, 81.4), (1, 81.0),
    ]

    /// The same sample series as plain `WeighIn`s, for previews that only
    /// need the pure logic (no container), like `BodyWeightChart`'s own.
    static var sampleWeighIns: [BodyWeightTrend.WeighIn] {
        let calendar = Calendar.current
        let now = Date()
        return sampleOffsetsAndWeights.compactMap { entry in
            guard let date = calendar.date(byAdding: .day, value: -entry.daysAgo, to: now) else { return nil }
            return BodyWeightTrend.WeighIn(dayKey: DayKey.make(from: date, calendar: calendar), kg: entry.kg)
        }
    }

    /// Inserts the same series as `BodyMeasurement` rows, for previews that
    /// query a container: `BodyWeightView` and `BodyWeightCard`.
    @discardableResult
    static func seedWeighIns(in context: ModelContext) -> [BodyMeasurement] {
        let calendar = Calendar.current
        let now = Date()

        let measurements: [BodyMeasurement] = sampleOffsetsAndWeights.compactMap { entry in
            guard let date = calendar.date(byAdding: .day, value: -entry.daysAgo, to: now) else { return nil }
            return BodyMeasurement(recordedAt: date, type: .bodyWeight, value: entry.kg, calendar: calendar)
        }
        measurements.forEach { context.insert($0) }
        try? context.save()
        return measurements
    }
}
