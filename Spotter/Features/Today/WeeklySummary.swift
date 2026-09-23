import Foundation

/// Pure maths behind the Today "week so far" card and the streak card's
/// weekly figures: days logged, average kcal, protein- and water-goal hit
/// days, workouts and volume, cardio minutes, and trend-weight change.
///
/// Kept free of SwiftUI and SwiftData, over `Set`/`Dictionary` day keys and
/// plain values — mirroring `DashboardAggregation` and `WaterAggregation` —
/// so it can be unit tested directly and reused between `StreakSummaryCard`
/// and `WeeklySummaryCard` without either owning the other's query.
enum WeeklySummary {

    /// The goals a day's totals are compared against.
    struct Goals: Hashable, Sendable {
        var kcal: Double
        var proteinG: Double
        var waterML: Double
    }

    struct Result: Hashable, Sendable {
        var weekKeys: [String]
        /// Days in `weekKeys` with at least one diary entry (Decision 6).
        var daysLogged: Int
        /// Mean of `effectiveKcal` across logged days only — an unlogged day
        /// does not pull the average toward zero. Nil when nothing was
        /// logged this week at all.
        var averageKcal: Double?
        /// Days whose total protein met or beat the goal. Zero when the
        /// protein goal itself is unset, rather than counting every day as a
        /// trivial "hit".
        var proteinGoalHitDays: Int
        /// Days whose water total met or beat the goal.
        var waterGoalHitDays: Int
        /// Days with a finished `Workout` (a cardio-only day is *not* counted
        /// here — see `trainedDays` below for that).
        var workoutDays: Int
        /// Days trained by either definition: a finished `Workout` or any
        /// `CardioEntry` (Decision 5).
        var trainedDays: Int
        /// Total tonnage across every workout this week.
        var totalVolumeKG: Double
        /// Total cardio time this week, in minutes.
        var cardioMinutes: Double
        /// Change in trend body weight over the week, from
        /// `BodyWeightTrend.weeklyRate`. Nil with under a week of weigh-in
        /// history, or no weigh-ins at all.
        var trendWeightChangeKG: Double?

        var totalDays: Int { weekKeys.count }
    }

    /// Builds the week's summary from per-day dictionaries, matching the
    /// pattern `DashboardAggregation.weekGlances` and
    /// `WaterAggregation.dailyTotals` use — callers group their `@Query`
    /// results by `dayKey` and pass the dictionaries in.
    static func make(
        weekKeys: [String],
        diaryByDay: [String: [Nutrients]],
        waterByDay: [String: Double],
        goals: Goals,
        workoutDayKeys: Set<String>,
        workoutVolumeByDay: [String: Double],
        cardioSecondsByDay: [String: Double],
        trendWeightChangeKG: Double?
    ) -> Result {
        let loggedKeys = weekKeys.filter { !(diaryByDay[$0] ?? []).isEmpty }

        let loggedDayKcal = loggedKeys.compactMap { key in
            Nutrients.total(of: diaryByDay[key] ?? []).effectiveKcal
        }
        let averageKcal = loggedDayKcal.isEmpty
            ? nil
            : loggedDayKcal.reduce(0, +) / Double(loggedDayKcal.count)

        let proteinGoalHitDays: Int = {
            guard goals.proteinG > 0 else { return 0 }
            return weekKeys.filter { key in
                let total = Nutrients.total(of: diaryByDay[key] ?? []).proteinG ?? 0
                return total >= goals.proteinG
            }.count
        }()

        let waterGoalHitDays: Int = {
            guard goals.waterML > 0 else { return 0 }
            return weekKeys.filter { (waterByDay[$0] ?? 0) >= goals.waterML }.count
        }()

        let cardioDayKeys = Set(cardioSecondsByDay.keys)
        let trainedDayKeys = workoutDayKeys.union(cardioDayKeys)

        let workoutDays = weekKeys.filter { workoutDayKeys.contains($0) }.count
        let trainedDays = weekKeys.filter { trainedDayKeys.contains($0) }.count
        let totalVolumeKG = weekKeys.reduce(0) { $0 + (workoutVolumeByDay[$1] ?? 0) }
        let cardioSeconds = weekKeys.reduce(0) { $0 + (cardioSecondsByDay[$1] ?? 0) }

        return Result(
            weekKeys: weekKeys,
            daysLogged: loggedKeys.count,
            averageKcal: averageKcal,
            proteinGoalHitDays: proteinGoalHitDays,
            waterGoalHitDays: waterGoalHitDays,
            workoutDays: workoutDays,
            trainedDays: trainedDays,
            totalVolumeKG: totalVolumeKG,
            cardioMinutes: cardioSeconds / 60,
            trendWeightChangeKG: trendWeightChangeKG
        )
    }

    /// Day keys for the calendar week containing `now`, clipped so the last
    /// key is today rather than running to the end of the week.
    ///
    /// Built from `calendar.dateInterval(of: .weekOfYear, for:)`, which
    /// respects `calendar.firstWeekday` — a Monday-first and a Sunday-first
    /// calendar give different weeks for the same date (Decision 7).
    static func weekKeys(now: Date = Date(), calendar: Calendar = .current) -> [String] {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: now) else {
            return [DayKey.make(from: now, calendar: calendar)]
        }

        let todayKey = DayKey.make(from: now, calendar: calendar)
        var keys: [String] = []
        var cursor = interval.start
        while cursor < interval.end {
            let key = DayKey.make(from: cursor, calendar: calendar)
            keys.append(key)
            if key == todayKey { break }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return keys
    }
}
