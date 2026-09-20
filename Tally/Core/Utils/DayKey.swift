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
/// The formatter is fixed to the POSIX locale and the Gregorian calendar so the
/// *format* of the key is stable, while the day boundary itself comes from the
/// caller's calendar — which is what should follow the user's time zone.
enum DayKey {
    /// `yyyy-MM-dd`, locale-independent.
    nonisolated(unsafe) private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let lock = NSLock()

    /// The day key for a date, in the given calendar's time zone.
    static func make(from date: Date, calendar: Calendar = .current) -> String {
        lock.lock()
        defer { lock.unlock() }
        formatter.timeZone = calendar.timeZone
        return formatter.string(from: date)
    }

    /// Parse a day key back to the start of that day. Nil if malformed.
    static func date(from key: String, calendar: Calendar = .current) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        formatter.timeZone = calendar.timeZone
        return formatter.date(from: key)
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
}

extension Date {
    /// Convenience for the common case.
    var dayKey: String { DayKey.make(from: self) }
}
