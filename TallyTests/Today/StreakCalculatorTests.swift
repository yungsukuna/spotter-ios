import Foundation
import Testing

@testable import Tally

/// The pure maths behind the Today logging streak. See `StreakCalculator`.
@Suite("StreakCalculator")
struct StreakCalculatorTests {

    /// A fixed calendar so these tests do not depend on the machine's zone.
    private static func calendar(_ identifier: String = "UTC") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier) ?? .gmt
        return calendar
    }

    /// A fixed "now", 2025-09-19 12:00 UTC, plus a helper to build the key
    /// `daysAgo` days before it, so tests don't depend on when they run.
    private static let anchor = Date(timeIntervalSince1970: 1_758_283_200)

    private func key(daysAgo: Int, from anchor: Date = Self.anchor, calendar: Calendar) -> String {
        guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: anchor) else { return "" }
        return DayKey.make(from: date, calendar: calendar)
    }

    // MARK: - currentStreak

    @Test("An empty set gives a zero streak with today pending")
    func emptySetGivesZero() {
        let calendar = Self.calendar()
        let result = StreakCalculator.currentStreak(days: [], today: Self.anchor, calendar: calendar)
        #expect(result.length == 0)
        #expect(result.todayPending)
    }

    @Test("Today pending continues yesterday's streak")
    func todayPendingContinuesYesterdaysStreak() {
        let calendar = Self.calendar()
        let days: Set<String> = [
            key(daysAgo: 1, calendar: calendar),
            key(daysAgo: 2, calendar: calendar),
            key(daysAgo: 3, calendar: calendar),
        ]

        let result = StreakCalculator.currentStreak(days: days, today: Self.anchor, calendar: calendar)

        #expect(result.todayPending)
        #expect(result.length == 3)
    }

    @Test("Today already logged is included and not pending")
    func todayLoggedIsIncluded() {
        let calendar = Self.calendar()
        let days: Set<String> = [
            key(daysAgo: 0, calendar: calendar),
            key(daysAgo: 1, calendar: calendar),
        ]

        let result = StreakCalculator.currentStreak(days: days, today: Self.anchor, calendar: calendar)

        #expect(!result.todayPending)
        #expect(result.length == 2)
    }

    @Test("One gap breaks the streak")
    func oneGapBreaksStreak() {
        let calendar = Self.calendar()
        // Today and yesterday logged, the day before that missing, then an
        // older run further back — the gap must stop the count cold.
        let days: Set<String> = [
            key(daysAgo: 0, calendar: calendar),
            key(daysAgo: 1, calendar: calendar),
            key(daysAgo: 3, calendar: calendar),
            key(daysAgo: 4, calendar: calendar),
        ]

        let result = StreakCalculator.currentStreak(days: days, today: Self.anchor, calendar: calendar)

        #expect(!result.todayPending)
        #expect(result.length == 2)
    }

    @Test("A streak spanning the Auckland September DST transition counts calendar days, not seconds")
    func streakAcrossSeptemberDST() throws {
        // New Zealand DST begins 28 September 2025 — the 23-hour day. A
        // streak of four consecutive calendar days straddling it must still
        // read as 4, not be thrown off by the short day.
        let calendar = Self.calendar("Pacific/Auckland")
        var components = DateComponents()
        components.year = 2025
        components.month = 9
        components.day = 29
        components.hour = 12
        let today = try #require(calendar.date(from: components))

        let days: Set<String> = Set((0..<4).map { key(daysAgo: $0, from: today, calendar: calendar) })

        let result = StreakCalculator.currentStreak(days: days, today: today, calendar: calendar)

        #expect(!result.todayPending)
        #expect(result.length == 4)
    }

    @Test("A streak spanning the Auckland April DST transition counts calendar days, not seconds")
    func streakAcrossAprilDST() throws {
        // New Zealand daylight saving ends 6 April 2025 — the 25-hour day.
        let calendar = Self.calendar("Pacific/Auckland")
        var components = DateComponents()
        components.year = 2025
        components.month = 4
        components.day = 7
        components.hour = 12
        let today = try #require(calendar.date(from: components))

        let days: Set<String> = Set((0..<4).map { key(daysAgo: $0, from: today, calendar: calendar) })

        let result = StreakCalculator.currentStreak(days: days, today: today, calendar: calendar)

        #expect(!result.todayPending)
        #expect(result.length == 4)
    }

    @Test("A streak spanning a month boundary counts correctly")
    func streakAcrossMonthBoundary() throws {
        let calendar = Self.calendar()
        var components = DateComponents()
        components.year = 2025
        components.month = 11
        components.day = 2
        let today = try #require(calendar.date(from: components))

        // 2025-10-31, 11-01, 11-02.
        let days: Set<String> = Set((0..<3).map { key(daysAgo: $0, from: today, calendar: calendar) })

        let result = StreakCalculator.currentStreak(days: days, today: today, calendar: calendar)

        #expect(!result.todayPending)
        #expect(result.length == 3)
    }

    @Test("A streak spanning a year boundary counts correctly")
    func streakAcrossYearBoundary() throws {
        let calendar = Self.calendar()
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 2
        let today = try #require(calendar.date(from: components))

        // 2025-12-31, 2026-01-01, 2026-01-02.
        let days: Set<String> = Set((0..<3).map { key(daysAgo: $0, from: today, calendar: calendar) })

        let result = StreakCalculator.currentStreak(days: days, today: today, calendar: calendar)

        #expect(!result.todayPending)
        #expect(result.length == 3)
    }

    // MARK: - longestStreak

    @Test("Longest streak over an empty set is zero")
    func longestStreakOverEmptySet() {
        #expect(StreakCalculator.longestStreak(days: []) == 0)
    }

    @Test("The longest streak is found in the middle of the data, not just at the ends")
    func longestStreakFoundInTheMiddle() {
        let calendar = Self.calendar()
        // A 1-day run, a gap, a 5-day run in the middle, a gap, a 2-day run.
        var days: Set<String> = []
        days.insert(key(daysAgo: 20, calendar: calendar))
        for offset in 10...14 {
            days.insert(key(daysAgo: offset, calendar: calendar))
        }
        days.insert(key(daysAgo: 1, calendar: calendar))
        days.insert(key(daysAgo: 0, calendar: calendar))

        #expect(StreakCalculator.longestStreak(days: days, calendar: calendar) == 5)
    }

    @Test("A single day is a streak of length one")
    func singleDayIsStreakOfOne() {
        let calendar = Self.calendar()
        #expect(StreakCalculator.longestStreak(days: [key(daysAgo: 0, calendar: calendar)], calendar: calendar) == 1)
    }
}
