import Foundation

/// Pure maths behind the Today logging streak: how many consecutive days in
/// a row have at least one entry, and the longest such run in history.
///
/// Operates over `Set<String>` day keys rather than model types, so it can be
/// unit tested without a `ModelContainer` and reused for any "streak of days
/// with X" — today it is fed the set of days with at least one `DiaryEntry`
/// (Decision 6 in `docs/PHASE2-PLAN.md`).
///
/// **Time zones:** a `dayKey` is frozen at log time in the device's zone.
/// Travelling can create a gap or a double day in the underlying data. That
/// is accepted rather than corrected for — the streak runs over keys, not
/// instants, which keeps it deterministic and reproducible server-side in
/// Phase 3.
enum StreakCalculator {

    /// The current streak's length, and whether it depends on logging
    /// something today to keep going.
    struct StreakResult: Hashable, Sendable {
        /// Consecutive days up to and including yesterday if `todayPending`,
        /// otherwise up to and including today.
        var length: Int
        /// True when today is not yet in `days` — the streak shown is
        /// "still alive, logging today keeps it going", not "already includes
        /// today".
        var todayPending: Bool
    }

    /// Walks back from today (or from yesterday, if today has no entry yet)
    /// counting consecutive logged days.
    ///
    /// Steps a day at a time via `calendar.date(byAdding: .day, value: -1)`
    /// applied to `DayKey.date(from:)`, then re-keys with `DayKey.make(from:)`
    /// — never raw 86_400-second arithmetic, which drifts across a
    /// daylight-saving transition.
    static func currentStreak(
        days: Set<String>,
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> StreakResult {
        let todayKey = DayKey.make(from: today, calendar: calendar)
        let todayPending = !days.contains(todayKey)

        var cursorKey: String
        if todayPending {
            guard
                let todayDate = DayKey.date(from: todayKey, calendar: calendar),
                let yesterday = calendar.date(byAdding: .day, value: -1, to: todayDate)
            else {
                return StreakResult(length: 0, todayPending: true)
            }
            cursorKey = DayKey.make(from: yesterday, calendar: calendar)
        } else {
            cursorKey = todayKey
        }

        var length = 0
        while days.contains(cursorKey) {
            length += 1
            guard
                let cursorDate = DayKey.date(from: cursorKey, calendar: calendar),
                let previous = calendar.date(byAdding: .day, value: -1, to: cursorDate)
            else {
                break
            }
            cursorKey = DayKey.make(from: previous, calendar: calendar)
        }

        return StreakResult(length: length, todayPending: todayPending)
    }

    /// The longest run of consecutive day keys anywhere in `days`, not just
    /// the one ending today.
    ///
    /// Day keys sort lexically the same as chronologically (zero-padded
    /// `yyyy-MM-dd`), so keys are sorted as strings first and only parsed to
    /// dates to measure the gap between consecutive entries — the same
    /// calendar-day-count approach as `currentStreak`, never a raw time
    /// interval.
    static func longestStreak(days: Set<String>, calendar: Calendar = .current) -> Int {
        guard !days.isEmpty else { return 0 }

        let sortedKeys = days.sorted()
        var longest = 0
        var current = 0
        var previousDate: Date?

        for key in sortedKeys {
            guard let date = DayKey.date(from: key, calendar: calendar) else { continue }
            if let previousDate {
                let gap = calendar.dateComponents([.day], from: previousDate, to: date).day ?? 0
                current = gap == 1 ? current + 1 : 1
            } else {
                current = 1
            }
            longest = max(longest, current)
            previousDate = date
        }

        return longest
    }
}
