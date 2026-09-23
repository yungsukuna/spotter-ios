import Foundation
import Testing

@testable import Spotter

/// The pure maths behind the Today "week so far" card. See `WeeklySummary`.
@Suite("WeeklySummary")
struct WeeklySummaryTests {

    /// A fixed calendar so these tests do not depend on the machine's zone.
    private static func calendar(_ identifier: String = "UTC", firstWeekday: Int? = nil) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier) ?? .gmt
        if let firstWeekday {
            calendar.firstWeekday = firstWeekday
        }
        return calendar
    }

    // MARK: - weekKeys

    @Test("The week clips at today rather than running to the end of the week")
    func weekClipsAtToday() {
        // Sunday-first calendar: 2025-09-17 is a Wednesday, so the week
        // started Sunday 2025-09-14. Clipped, that's 4 keys: 14, 15, 16, 17.
        let calendar = Self.calendar(firstWeekday: 1)
        var components = DateComponents()
        components.year = 2025
        components.month = 9
        components.day = 17
        let now = calendar.date(from: components)!

        let keys = WeeklySummary.weekKeys(now: now, calendar: calendar)

        #expect(keys == ["2025-09-14", "2025-09-15", "2025-09-16", "2025-09-17"])
        #expect(keys.last == DayKey.make(from: now, calendar: calendar))
    }

    @Test("A Monday-first calendar gives a different week than a Sunday-first calendar for the same date")
    func mondayFirstVsSundayFirst() {
        var components = DateComponents()
        components.year = 2025
        components.month = 9
        components.day = 17 // Wednesday.

        let sundayFirst = Self.calendar(firstWeekday: 1)
        let mondayFirst = Self.calendar(firstWeekday: 2)
        let now = sundayFirst.date(from: components)!

        let sundayFirstKeys = WeeklySummary.weekKeys(now: now, calendar: sundayFirst)
        let mondayFirstKeys = WeeklySummary.weekKeys(now: now, calendar: mondayFirst)

        // Sunday-first: week started Sun 14th. Monday-first: week started Mon 15th.
        #expect(sundayFirstKeys.first == "2025-09-14")
        #expect(mondayFirstKeys.first == "2025-09-15")
        #expect(sundayFirstKeys.last == mondayFirstKeys.last)
        #expect(sundayFirstKeys.count == mondayFirstKeys.count + 1)
    }

    // MARK: - make

    @Test("Average kcal ignores unlogged days and uses effectiveKcal")
    func averageKcalIgnoresUnloggedDays() {
        let keys = ["2026-09-14", "2026-09-15", "2026-09-16"]
        // Day 1: kcal known directly. Day 2: unlogged (no diary entries at
        // all — must not pull the average toward zero). Day 3: kcal unknown
        // but derivable from macros via effectiveKcal.
        let diaryByDay: [String: [Nutrients]] = [
            "2026-09-14": [Nutrients(kcal: 2000)],
            "2026-09-16": [Nutrients(kcal: nil, proteinG: 50, carbsG: 100, fatG: 20)],
        ]

        let result = WeeklySummary.make(
            weekKeys: keys,
            diaryByDay: diaryByDay,
            waterByDay: [:],
            goals: WeeklySummary.Goals(kcal: 2000, proteinG: 150, waterML: 2500),
            workoutDayKeys: [],
            workoutVolumeByDay: [:],
            cardioSecondsByDay: [:],
            trendWeightChangeKG: nil
        )

        // Day 3's effectiveKcal: 50*4 + 100*4 + 20*9 = 200 + 400 + 180 = 780.
        let expectedAverage = (2000.0 + 780.0) / 2.0

        #expect(result.daysLogged == 2)
        #expect(result.averageKcal != nil)
        if let average = result.averageKcal {
            #expect(abs(average - expectedAverage) < 0.0001)
        }
    }

    @Test("Average kcal is nil when nothing was logged all week")
    func averageKcalNilWithNothingLogged() {
        let result = WeeklySummary.make(
            weekKeys: ["2026-09-14", "2026-09-15"],
            diaryByDay: [:],
            waterByDay: [:],
            goals: WeeklySummary.Goals(kcal: 2000, proteinG: 150, waterML: 2500),
            workoutDayKeys: [],
            workoutVolumeByDay: [:],
            cardioSecondsByDay: [:],
            trendWeightChangeKG: nil
        )

        #expect(result.daysLogged == 0)
        #expect(result.averageKcal == nil)
    }

    @Test("Protein- and water-goal hit days count only days meeting or beating the goal")
    func goalHitDaysCountMeetingOrBeatingDays() {
        let keys = ["2026-09-14", "2026-09-15", "2026-09-16"]
        let diaryByDay: [String: [Nutrients]] = [
            "2026-09-14": [Nutrients(proteinG: 150)], // exactly meets goal
            "2026-09-15": [Nutrients(proteinG: 80)], // under goal
        ]
        let waterByDay: [String: Double] = [
            "2026-09-14": 3000, // over goal
            "2026-09-16": 1000, // under goal
        ]

        let result = WeeklySummary.make(
            weekKeys: keys,
            diaryByDay: diaryByDay,
            waterByDay: waterByDay,
            goals: WeeklySummary.Goals(kcal: 2000, proteinG: 150, waterML: 2500),
            workoutDayKeys: [],
            workoutVolumeByDay: [:],
            cardioSecondsByDay: [:],
            trendWeightChangeKG: nil
        )

        #expect(result.proteinGoalHitDays == 1)
        #expect(result.waterGoalHitDays == 1)
    }

    @Test("Goal hit days are zero when the goal itself is unset, not a division-by-zero crash")
    func goalHitDaysGuardsZeroGoal() {
        let result = WeeklySummary.make(
            weekKeys: ["2026-09-14"],
            diaryByDay: ["2026-09-14": [Nutrients(proteinG: 10)]],
            waterByDay: ["2026-09-14": 10],
            goals: WeeklySummary.Goals(kcal: 0, proteinG: 0, waterML: 0),
            workoutDayKeys: [],
            workoutVolumeByDay: [:],
            cardioSecondsByDay: [:],
            trendWeightChangeKG: nil
        )

        #expect(result.proteinGoalHitDays == 0)
        #expect(result.waterGoalHitDays == 0)
    }

    @Test("A cardio-only day counts as trained but not as a workout day")
    func cardioOnlyDayCountsAsTrainedNotAsWorkout() {
        let keys = ["2026-09-14", "2026-09-15", "2026-09-16"]

        let result = WeeklySummary.make(
            weekKeys: keys,
            diaryByDay: [:],
            waterByDay: [:],
            goals: WeeklySummary.Goals(kcal: 2000, proteinG: 150, waterML: 2500),
            workoutDayKeys: ["2026-09-14"],
            workoutVolumeByDay: ["2026-09-14": 5000],
            cardioSecondsByDay: ["2026-09-15": 1800],
            trendWeightChangeKG: nil
        )

        #expect(result.workoutDays == 1)
        #expect(result.trainedDays == 2)
        #expect(result.totalVolumeKG == 5000)
        #expect(result.cardioMinutes == 30)
    }

    @Test("Days outside the week key list are ignored even if present in the by-day maps")
    func daysOutsideWeekAreIgnored() {
        let result = WeeklySummary.make(
            weekKeys: ["2026-09-14"],
            diaryByDay: ["2026-09-01": [Nutrients(kcal: 9999)]],
            waterByDay: ["2026-09-01": 9999],
            goals: WeeklySummary.Goals(kcal: 2000, proteinG: 150, waterML: 2500),
            workoutDayKeys: ["2026-09-01"],
            workoutVolumeByDay: ["2026-09-01": 9999],
            cardioSecondsByDay: ["2026-09-01": 9999],
            trendWeightChangeKG: nil
        )

        #expect(result.daysLogged == 0)
        #expect(result.averageKcal == nil)
        #expect(result.workoutDays == 0)
        #expect(result.trainedDays == 0)
        #expect(result.totalVolumeKG == 0)
        #expect(result.cardioMinutes == 0)
    }

    @Test("Trend weight change passes through unchanged")
    func trendWeightChangePassesThrough() {
        let result = WeeklySummary.make(
            weekKeys: ["2026-09-14"],
            diaryByDay: [:],
            waterByDay: [:],
            goals: WeeklySummary.Goals(kcal: 2000, proteinG: 150, waterML: 2500),
            workoutDayKeys: [],
            workoutVolumeByDay: [:],
            cardioSecondsByDay: [:],
            trendWeightChangeKG: -0.4
        )

        #expect(result.trendWeightChangeKG == -0.4)
    }
}
