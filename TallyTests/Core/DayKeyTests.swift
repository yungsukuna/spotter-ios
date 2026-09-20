import Foundation
import Testing

@testable import Tally

@Suite("DayKey")
struct DayKeyTests {

    /// A fixed calendar so these tests do not depend on the machine's zone.
    private static func calendar(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier) ?? .gmt
        return calendar
    }

    @Test("Keys are formatted yyyy-MM-dd")
    func keyFormat() {
        let date = Date(timeIntervalSince1970: 1_758_240_000) // 2025-09-19 UTC
        let key = DayKey.make(from: date, calendar: Self.calendar("UTC"))

        #expect(key.count == 10)
        #expect(key.wholeMatch(of: /\d{4}-\d{2}-\d{2}/) != nil)
    }

    @Test("A key round-trips back to the start of that day")
    func roundTrip() throws {
        let calendar = Self.calendar("UTC")
        let original = Date(timeIntervalSince1970: 1_758_283_845) // mid-afternoon
        let key = DayKey.make(from: original, calendar: calendar)

        let parsed = try #require(DayKey.date(from: key, calendar: calendar))
        // Parsing yields midnight, so it re-keys to the same day.
        #expect(DayKey.make(from: parsed, calendar: calendar) == key)
    }

    @Test("A malformed key does not parse")
    func malformedKey() {
        #expect(DayKey.date(from: "not-a-date") == nil)
        #expect(DayKey.date(from: "") == nil)
    }

    @Test("The day boundary follows the calendar's time zone")
    func dayBoundaryIsZoneRelative() {
        // 2025-09-19 23:30 UTC. In Auckland (UTC+12) that is already the 20th.
        // This is exactly why entries carry a precomputed key rather than being
        // queried by UTC date range.
        let date = Date(timeIntervalSince1970: 1_758_325_800)

        let utcKey = DayKey.make(from: date, calendar: Self.calendar("UTC"))
        let aucklandKey = DayKey.make(from: date, calendar: Self.calendar("Pacific/Auckland"))

        #expect(utcKey != aucklandKey)
    }

    @Test("Keys are stable across a daylight-saving transition")
    func stableAcrossDST() {
        // New Zealand DST begins on 28 September 2025. Midday either side must
        // still produce that calendar day's key — the case a naive
        // "startOfDay + 86400" range calculation gets wrong.
        let calendar = Self.calendar("Pacific/Auckland")

        var components = DateComponents()
        components.year = 2025
        components.month = 9
        components.day = 28
        components.hour = 12
        let duringTransitionDay = calendar.date(from: components)

        #expect(duringTransitionDay != nil)
        if let duringTransitionDay {
            #expect(DayKey.make(from: duringTransitionDay, calendar: calendar) == "2025-09-28")
        }
    }

    @Test("A run of keys is oldest first and the right length")
    func keyRuns() {
        let calendar = Self.calendar("UTC")
        let end = Date(timeIntervalSince1970: 1_758_240_000)
        let keys = DayKey.keys(endingOn: end, count: 7, calendar: calendar)

        #expect(keys.count == 7)
        #expect(keys == keys.sorted(), "keys should be in ascending date order")
        #expect(keys.last == DayKey.make(from: end, calendar: calendar))
    }

    @Test("A run of zero or fewer days is empty")
    func emptyKeyRun() {
        #expect(DayKey.keys(endingOn: Date(), count: 0).isEmpty)
        #expect(DayKey.keys(endingOn: Date(), count: -3).isEmpty)
    }
}
