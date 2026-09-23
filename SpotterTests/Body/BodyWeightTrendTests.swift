import Foundation
import SwiftData
import Testing

@testable import Spotter

@Suite("BodyWeightTrend")
struct BodyWeightTrendTests {

    /// A fixed calendar so these tests do not depend on the machine's zone.
    private static func calendar(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier) ?? .gmt
        return calendar
    }

    /// A day key `daysAgo` days before a fixed anchor date, so tests don't
    /// depend on when they happen to run.
    private func dayKey(daysAgo: Int, calendar: Calendar) -> String {
        let anchor = Date(timeIntervalSince1970: 1_758_240_000) // 2025-09-19 UTC
        guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: anchor) else { return "" }
        return DayKey.make(from: date, calendar: calendar)
    }

    @Test("A constant series stays constant")
    func constantSeriesStaysConstant() {
        let calendar = Self.calendar("UTC")
        let weighIns = (0..<5).map { offset in
            BodyWeightTrend.WeighIn(dayKey: dayKey(daysAgo: 4 - offset, calendar: calendar), kg: 80)
        }

        let points = BodyWeightTrend.trend(BodyWeightTrend.dailyMeans(weighIns), calendar: calendar)

        #expect(points.count == 5)
        #expect(points.allSatisfy { $0.trend == 80 })
    }

    @Test("A step change converges to exactly 10% of the step after 1 day")
    func stepChangeConvergesByTenPercentAfterOneDay() {
        let calendar = Self.calendar("UTC")
        let means: [(dayKey: String, kg: Double)] = [
            (dayKey: dayKey(daysAgo: 1, calendar: calendar), kg: 80),
            (dayKey: dayKey(daysAgo: 0, calendar: calendar), kg: 90),
        ]

        let points = BodyWeightTrend.trend(means, alpha: 0.1, calendar: calendar)

        #expect(points.count == 2)
        #expect(points[0].trend == 80)
        #expect(abs(points[1].trend - 81.0) < 0.0001)
    }

    @Test("A 3-day gap equals three single steps of the same value")
    func threeDayGapEqualsThreeSingleSteps() {
        let calendar = Self.calendar("UTC")
        let means: [(dayKey: String, kg: Double)] = [
            (dayKey: dayKey(daysAgo: 3, calendar: calendar), kg: 80),
            (dayKey: dayKey(daysAgo: 0, calendar: calendar), kg: 90),
        ]

        let points = BodyWeightTrend.trend(means, alpha: 0.1, calendar: calendar)

        var stepwise = 80.0
        for _ in 0..<3 {
            stepwise += 0.1 * (90.0 - stepwise)
        }

        #expect(points.count == 2)
        #expect(abs(points[1].trend - stepwise) < 0.0001)
    }

    @Test("Several weigh-ins on one day are averaged")
    func multipleWeighInsOnOneDayAreAveraged() {
        let calendar = Self.calendar("UTC")
        let key = dayKey(daysAgo: 0, calendar: calendar)
        let weighIns = [
            BodyWeightTrend.WeighIn(dayKey: key, kg: 80),
            BodyWeightTrend.WeighIn(dayKey: key, kg: 82),
            BodyWeightTrend.WeighIn(dayKey: key, kg: 81),
        ]

        let means = BodyWeightTrend.dailyMeans(weighIns)

        #expect(means.count == 1)
        #expect(abs(means[0].kg - 81.0) < 0.0001)
    }

    @Test("Empty input gives an empty trend and a nil latest value")
    func emptyInputGivesEmptyResult() {
        #expect(BodyWeightTrend.dailyMeans([]).isEmpty)
        #expect(BodyWeightTrend.trend([]).isEmpty)
        #expect(BodyWeightTrend.latestTrendKG(from: []) == nil)
    }

    @Test("A gap spanning a DST change counts calendar days, not seconds")
    func gapAcrossDSTCountsCalendarDays() throws {
        // NZ daylight saving began 28 September 2025, so the calendar day
        // spanning the transition is only 23 hours long. A naive
        // 86_400-second gap calculation would misjudge the day count here;
        // `Calendar.dateComponents([.day])` must not.
        let calendar = Self.calendar("Pacific/Auckland")

        var beforeComponents = DateComponents()
        beforeComponents.year = 2025
        beforeComponents.month = 9
        beforeComponents.day = 26
        var afterComponents = DateComponents()
        afterComponents.year = 2025
        afterComponents.month = 9
        afterComponents.day = 29

        let before = try #require(calendar.date(from: beforeComponents))
        let after = try #require(calendar.date(from: afterComponents))

        let means: [(dayKey: String, kg: Double)] = [
            (dayKey: DayKey.make(from: before, calendar: calendar), kg: 80),
            (dayKey: DayKey.make(from: after, calendar: calendar), kg: 90),
        ]

        let points = BodyWeightTrend.trend(means, alpha: 0.1, calendar: calendar)

        // Exactly 3 calendar days apart (26th -> 29th) regardless of the
        // 23-hour DST day in between.
        var stepwise = 80.0
        for _ in 0..<3 {
            stepwise += 0.1 * (90.0 - stepwise)
        }

        #expect(points.count == 2)
        #expect(abs(points[1].trend - stepwise) < 0.0001)
    }

    @Test("Weekly rate compares the latest trend to a week or more prior")
    func weeklyRateComparesAWeekBack() {
        let calendar = Self.calendar("UTC")
        let means: [(dayKey: String, kg: Double)] = (0..<10).map { offset in
            (dayKey: dayKey(daysAgo: 9 - offset, calendar: calendar), kg: 80.0 - Double(offset) * 0.1)
        }

        let points = BodyWeightTrend.trend(means, calendar: calendar)
        let rate = BodyWeightTrend.weeklyRate(points, calendar: calendar)

        #expect(rate != nil)
        // The series trends down, so the weekly rate should be negative.
        if let rate {
            #expect(rate < 0)
        }
    }

    @Test("Weekly rate is nil with under a week of history")
    func weeklyRateNilUnderAWeek() {
        let calendar = Self.calendar("UTC")
        let means: [(dayKey: String, kg: Double)] = (0..<3).map { offset in
            (dayKey: dayKey(daysAgo: 2 - offset, calendar: calendar), kg: 80)
        }

        let points = BodyWeightTrend.trend(means, calendar: calendar)

        #expect(BodyWeightTrend.weeklyRate(points, calendar: calendar) == nil)
    }

    @Test("Weekly rate is nil with no history")
    func weeklyRateNilWithNoHistory() {
        #expect(BodyWeightTrend.weeklyRate([]) == nil)
    }

    @Test("latestTrendKG(from:) matches the last trend point")
    func latestTrendKGMatchesLastPoint() {
        let calendar = Self.calendar("UTC")
        let weighIns = (0..<4).map { offset in
            BodyWeightTrend.WeighIn(dayKey: dayKey(daysAgo: 3 - offset, calendar: calendar), kg: 80 + Double(offset))
        }

        let expected = BodyWeightTrend.trend(BodyWeightTrend.dailyMeans(weighIns), calendar: calendar).last?.trend
        let actual = BodyWeightTrend.latestTrendKG(from: weighIns, calendar: calendar)

        #expect(actual == expected)
    }
}

@MainActor
@Suite("BodyWeightTrend + ModelContext")
struct BodyWeightTrendContextTests {

    private func makeContext() throws -> ModelContext {
        ModelContext(try SpotterSchema.makeContainer(inMemory: true))
    }

    @Test("latestTrendKG(in:) reads bodyWeight measurements and ignores other types")
    func latestTrendKGReadsBodyWeightOnly() throws {
        let context = try makeContext()
        let now = Date()

        context.insert(BodyMeasurement(recordedAt: now.addingTimeInterval(-2 * 86400), type: .bodyWeight, value: 80))
        context.insert(BodyMeasurement(recordedAt: now, type: .bodyWeight, value: 82))
        context.insert(BodyMeasurement(recordedAt: now, type: .waist, value: 90))
        try context.save()

        let trend = try #require(BodyWeightTrend.latestTrendKG(in: context))

        // Only the two bodyWeight rows should feed the trend; a waist
        // measurement of 90 would otherwise pull an 80/82 series far off.
        #expect(trend > 79 && trend < 83)
    }

    @Test("latestTrendKG(in:) is nil with no weigh-ins")
    func latestTrendKGNilWithNoData() throws {
        let context = try makeContext()
        #expect(BodyWeightTrend.latestTrendKG(in: context) == nil)
    }
}
