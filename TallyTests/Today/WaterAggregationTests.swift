import Foundation
import Testing

@testable import Tally

/// The pure maths behind the Water screen: daily totals, goal progress, and
/// the 7-day history series. See `WaterAggregation`.
@Suite("WaterAggregation")
struct WaterAggregationTests {

    @Test("Total sums volumes across records")
    func totalSumsVolumes() {
        let records = [
            WaterRecord(dayKey: "2026-09-19", volumeML: 250),
            WaterRecord(dayKey: "2026-09-19", volumeML: 500),
        ]
        #expect(WaterAggregation.totalML(records) == 750)
    }

    @Test("An empty day totals to zero")
    func emptyDayTotalsToZero() {
        #expect(WaterAggregation.totalML([]) == 0)
    }

    @Test("Progress fraction divides total by goal")
    func progressFractionDividesByGoal() {
        #expect(WaterAggregation.progressFraction(totalML: 1000, goalML: 2000) == 0.5)
    }

    @Test("Progress fraction is zero when the goal is zero, not a division-by-zero crash")
    func progressFractionGuardsZeroGoal() {
        #expect(WaterAggregation.progressFraction(totalML: 500, goalML: 0) == 0)
    }

    @Test("Progress fraction is not clamped, so callers can show overflow past the goal")
    func progressFractionCanExceedOne() {
        #expect(WaterAggregation.progressFraction(totalML: 3000, goalML: 2000) == 1.5)
    }

    @Test("Daily totals include days with no entries as zero, in the given order")
    func dailyTotalsFillsGapDays() {
        let records = [
            WaterRecord(dayKey: "2026-09-17", volumeML: 250),
            WaterRecord(dayKey: "2026-09-19", volumeML: 500),
            WaterRecord(dayKey: "2026-09-19", volumeML: 250),
        ]
        let keys = ["2026-09-17", "2026-09-18", "2026-09-19"]

        let totals = WaterAggregation.dailyTotals(records: records, keys: keys, goalML: 2000)

        #expect(totals.map(\.dayKey) == keys)
        #expect(totals[0].totalML == 250)
        // 2026-09-18 has no entries at all — it must still appear, at zero,
        // not be dropped from the series.
        #expect(totals[1].totalML == 0)
        #expect(totals[2].totalML == 750)
        #expect(totals.allSatisfy { $0.goalML == 2000 })
    }

    @Test("Daily totals over an empty history are still one entry per key, all zero")
    func dailyTotalsOverEmptyHistory() {
        let keys = ["2026-09-17", "2026-09-18"]
        let totals = WaterAggregation.dailyTotals(records: [], keys: keys, goalML: 2500)
        #expect(totals.map(\.totalML) == [0, 0])
    }

    @Test("A custom amount typed in fluid ounces stores millilitres")
    func customAmountConvertsToMillilitres() {
        // The spec example this mirrors: entering "16 fl oz" must store 473.18 ml.
        let stored = UnitConverter.volumeToMillilitres(16, from: .fluidOunces)
        #expect(abs(stored - 473.18) < 0.01)
    }

    @Test("A stored millilitre value round-trips through fluid ounces for display without drift")
    func displayRoundTripsThroughFluidOunces() {
        let storedML = 473.176
        let displayed = UnitConverter.volume(storedML, in: .fluidOunces)
        let backToStorage = UnitConverter.volumeToMillilitres(displayed, from: .fluidOunces)
        #expect(abs(backToStorage - storedML) < 0.000_001)
    }
}
