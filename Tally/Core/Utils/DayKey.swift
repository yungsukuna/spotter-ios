import Foundation

/// Converts dates to and from the `yyyy-MM-dd` string used to bucket entries
/// by day.
///
/// Every logged model carries a `dayKey` alongside its timestamp. The reason is
/// query correctness as much as speed: "everything logged today" expressed as a
/// date range has to get the day boundary right in the user's own calendar and
/// time zone, and gets it subtly wrong around daylight-saving transitions. A
/// string equality predicate on a precomputed key cannot drift.
///
/// Built from `Calendar` components rather than a `DateFormatter`. A shared
/// formatter would need its `timeZone` reassigned per call, which is a mutation
/// of shared state and so needs a lock; composing the digits directly is
/// thread-safe by construction, cheaper, and cannot be perturbed by the user's
/// locale or a non-Gregorian system calendar.
enum DayKey {

    /// The day key for a date, in the given calendar's time zone.
    static func make(from date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return format(
            year: components.year ?? 0,
            month: components.month ?? 0,
            day: components.day ?? 0
        )
    }

    /// Parse a day key back to the start of that day. Nil if malformed.
    static func date(from key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else { return nil }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        // Midnight local time, so the result re-keys to the same day.
        return calendar.date(from: components)
    }

    /// Today's key.
    static func today(calendar: Calendar = .current, now: Date = Date()) -> String {
        make(from: now, calendar: calendar)
    }

    /// Keys for `count` consecutive days ending on `date`, oldest first.
    /// Used by the weekly and monthly charts.
    static func keys(endingOn date: Date, count: Int, calendar: Calendar = .current) -> [String] {
        guard count > 0 else { return [] }
        return (0..<count)
            .compactMap { calendar.date(byAdding: .day, value: -$0, to: date) }
            .map { make(from: $0, calendar: calendar) }
            .reversed()
    }

    /// Zero-padded `yyyy-MM-dd`, without going through a formatter.
    private static func format(year: Int, month: Int, day: Int) -> String {
        var result = String(year)
        // Years are four digits in every date this app will ever see, but pad
        // defensively rather than emit a key that sorts wrongly.
        if result.count < 4 {
            result = String(repeating: "0", count: 4 - result.count) + result
        }
        result += month < 10 ? "-0\(month)" : "-\(month)"
        result += day < 10 ? "-0\(day)" : "-\(day)"
        return result
    }
}

extension Date {
    /// Convenience for the common case.
    var dayKey: String { DayKey.make(from: self) }
}
