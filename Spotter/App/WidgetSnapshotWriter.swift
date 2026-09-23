import Foundation
import SwiftData
import WidgetKit

/// Keeps the Home Screen widget's snapshot (`Shared/WidgetSnapshot.swift`) up
/// to date.
///
/// Called from explicit save points only — `SpotterApp` on `scenePhase` →
/// `.background`, and every screen that inserts or deletes a `DiaryEntry` or
/// `WaterEntry` — rather than from an invented change notification. See
/// Decision 12 in `docs/PHASE2-PLAN.md`.
@MainActor
enum WidgetSnapshotWriter {

    /// Builds today's snapshot from the current store and saves it, then asks
    /// WidgetKit to reload every widget timeline.
    static func refresh(in context: ModelContext) {
        let calendar = Calendar.current
        let now = Date()
        let dayKey = DayKey.make(from: now, calendar: calendar)

        let settings = UserSettings.current(in: context)

        let diaryDescriptor = FetchDescriptor<DiaryEntry>(
            predicate: #Predicate<DiaryEntry> { $0.dayKey == dayKey }
        )
        let diaryEntries = (try? context.fetch(diaryDescriptor)) ?? []

        let waterDescriptor = FetchDescriptor<WaterEntry>(
            predicate: #Predicate<WaterEntry> { $0.dayKey == dayKey }
        )
        let waterEntries = (try? context.fetch(waterDescriptor)) ?? []

        let snapshot = makeSnapshot(
            dayKey: dayKey,
            nutrientsLogged: diaryEntries.map(\.nutrients),
            kcalGoal: settings.dailyKcalGoal,
            waterVolumesML: waterEntries.map(\.volumeML),
            waterGoalML: settings.dailyWaterGoalML,
            volumeUnitRaw: settings.volumeUnitRaw,
            now: now
        )

        WidgetSnapshotStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// The pure part of ``refresh(in:)``: builds a snapshot from plain value
    /// inputs, with no SwiftData dependency, so it can be unit tested
    /// directly.
    ///
    /// Kcal uses `Nutrients.effectiveKcal` (the Atwater fallback when a source
    /// gives macros but no calorie figure) summed via `Nutrients.total`, and
    /// stays `nil` only when nothing logged that day carried any energy
    /// information at all — the same "unknown, not zero" rule the rest of the
    /// app follows.
    nonisolated static func makeSnapshot(
        dayKey: String,
        nutrientsLogged: [Nutrients],
        kcalGoal: Double,
        waterVolumesML: [Double],
        waterGoalML: Double,
        volumeUnitRaw: String,
        now: Date
    ) -> WidgetSnapshot {
        let totalNutrients = Nutrients.total(of: nutrientsLogged)
        let totalWaterML = waterVolumesML.reduce(0, +)

        return WidgetSnapshot(
            dayKey: dayKey,
            kcalConsumed: totalNutrients.effectiveKcal,
            kcalGoal: kcalGoal,
            waterML: totalWaterML,
            waterGoalML: waterGoalML,
            volumeUnitRaw: volumeUnitRaw,
            generatedAt: now
        )
    }
}
