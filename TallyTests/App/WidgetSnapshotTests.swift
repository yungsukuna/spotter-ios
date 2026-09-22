import Foundation
import Testing

@testable import Tally

@Suite("WidgetSnapshot")
struct WidgetSnapshotTests {

    // MARK: - Building

    @Test("Kcal sums effectiveKcal across the day's entries")
    func kcalSumsEffectiveKcal() {
        let entries = [
            Nutrients(kcal: 200, proteinG: 10),
            Nutrients(kcal: 150, proteinG: 5),
        ]
        let snapshot = WidgetSnapshotWriter.makeSnapshot(
            dayKey: "2025-09-19",
            nutrientsLogged: entries,
            kcalGoal: 2000,
            waterVolumesML: [250, 500],
            waterGoalML: 2500,
            volumeUnitRaw: VolumeUnit.millilitres.rawValue,
            now: Date()
        )

        #expect(snapshot.kcalConsumed == 350)
        #expect(snapshot.waterML == 750)
        #expect(snapshot.dayKey == "2025-09-19")
        #expect(snapshot.kcalGoal == 2000)
        #expect(snapshot.waterGoalML == 2500)
    }

    @Test("Kcal falls back to the Atwater estimate when no source gives a calorie figure")
    func kcalFallsBackToMacros() {
        // No `kcal`, but protein/carbs/fat are known — `effectiveKcal` should
        // estimate rather than the snapshot treating it as zero.
        let entries = [Nutrients(proteinG: 10, carbsG: 20, fatG: 5)]
        let snapshot = WidgetSnapshotWriter.makeSnapshot(
            dayKey: "2025-09-19",
            nutrientsLogged: entries,
            kcalGoal: 2000,
            waterVolumesML: [],
            waterGoalML: 2500,
            volumeUnitRaw: VolumeUnit.millilitres.rawValue,
            now: Date()
        )

        #expect(snapshot.kcalConsumed == Nutrients.total(of: entries).effectiveKcal)
        #expect(snapshot.kcalConsumed != nil)
    }

    @Test("Nil kcal stays nil when nothing logged carries any energy information")
    func nilKcalStaysNil() {
        let snapshot = WidgetSnapshotWriter.makeSnapshot(
            dayKey: "2025-09-19",
            nutrientsLogged: [],
            kcalGoal: 2000,
            waterVolumesML: [],
            waterGoalML: 2500,
            volumeUnitRaw: VolumeUnit.millilitres.rawValue,
            now: Date()
        )

        #expect(snapshot.kcalConsumed == nil)
        #expect(snapshot.waterML == 0)
    }

    // MARK: - Stale-day rule

    @Test("A snapshot from today is shown unchanged")
    func todaysSnapshotIsUnchanged() {
        let snapshot = WidgetSnapshot(
            dayKey: "2025-09-19",
            kcalConsumed: 500,
            kcalGoal: 2000,
            waterML: 750,
            waterGoalML: 2500,
            volumeUnitRaw: VolumeUnit.millilitres.rawValue,
            generatedAt: Date()
        )

        let display = snapshot.displayValues(today: "2025-09-19")

        #expect(display.kcalConsumed == 500)
        #expect(display.waterML == 750)
        #expect(display.dayKey == "2025-09-19")
    }

    @Test("A snapshot from an earlier day renders zero-consumed against the same goals")
    func staleSnapshotRendersZero() {
        let snapshot = WidgetSnapshot(
            dayKey: "2025-09-19",
            kcalConsumed: 1800,
            kcalGoal: 2000,
            waterML: 2400,
            waterGoalML: 2500,
            volumeUnitRaw: VolumeUnit.fluidOunces.rawValue,
            generatedAt: Date()
        )

        let display = snapshot.displayValues(today: "2025-09-20")

        #expect(display.dayKey == "2025-09-20")
        #expect(display.kcalConsumed == 0)
        #expect(display.waterML == 0)
        // Goals and unit preference carry over — only consumption resets.
        #expect(display.kcalGoal == 2000)
        #expect(display.waterGoalML == 2500)
        #expect(display.volumeUnitRaw == VolumeUnit.fluidOunces.rawValue)
    }

    // MARK: - Codable round trip

    @Test("A snapshot round-trips through JSON unchanged")
    func codableRoundTrip() throws {
        let original = WidgetSnapshot(
            dayKey: "2025-09-19",
            kcalConsumed: 1234.5,
            kcalGoal: 2000,
            waterML: 1750,
            waterGoalML: 2500,
            volumeUnitRaw: VolumeUnit.millilitres.rawValue,
            generatedAt: Date(timeIntervalSince1970: 1_758_240_000)
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)

        #expect(decoded == original)
    }

    @Test("A snapshot with a nil kcal round-trips as nil")
    func codableRoundTripPreservesNilKcal() throws {
        let original = WidgetSnapshot(
            dayKey: "2025-09-19",
            kcalConsumed: nil,
            kcalGoal: 2000,
            waterML: 0,
            waterGoalML: 2500,
            volumeUnitRaw: VolumeUnit.millilitres.rawValue,
            generatedAt: Date(timeIntervalSince1970: 1_758_240_000)
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)

        #expect(decoded.kcalConsumed == nil)
        #expect(decoded == original)
    }
}
