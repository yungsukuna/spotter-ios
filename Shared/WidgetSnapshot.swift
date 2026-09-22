import Foundation

/// The data the Home Screen / Lock Screen widget reads, written by the app
/// and read by the widget extension.
///
/// This is deliberately a **snapshot**, not a live read of the SwiftData
/// store (Decision 12 in `docs/PHASE2-PLAN.md`): the store stays in the
/// app's own container, and the widget only ever sees whatever was last
/// written here. It is stored as `Data` (JSON-encoded) in the App Group's
/// shared `UserDefaults` suite.
///
/// `Foundation` only — this file compiles into both the app target and the
/// widget extension target, and the extension must not link anything else
/// from the app.
struct WidgetSnapshot: Codable, Equatable, Sendable {
    /// `yyyy-MM-dd` the snapshot was built for, from `DayKey.make(from:)`.
    var dayKey: String
    /// Kcal consumed so far that day. `nil` when unknown — see the note on
    /// `Nutrients.kcal`: unknown must never be presented as zero.
    var kcalConsumed: Double?
    var kcalGoal: Double
    var waterML: Double
    var waterGoalML: Double
    /// Raw value of `VolumeUnit`, so the widget can format water without
    /// depending on anything beyond `Foundation` + `Enums.swift`.
    var volumeUnitRaw: String
    /// When this snapshot was built, for staleness diagnostics.
    var generatedAt: Date

    init(
        dayKey: String,
        kcalConsumed: Double?,
        kcalGoal: Double,
        waterML: Double,
        waterGoalML: Double,
        volumeUnitRaw: String,
        generatedAt: Date
    ) {
        self.dayKey = dayKey
        self.kcalConsumed = kcalConsumed
        self.kcalGoal = kcalGoal
        self.waterML = waterML
        self.waterGoalML = waterGoalML
        self.volumeUnitRaw = volumeUnitRaw
        self.generatedAt = generatedAt
    }

    /// What the widget should render for `dayKey`, given `today`.
    ///
    /// If the snapshot is from an earlier day than `today` — the app has not
    /// been foregrounded or logged into since midnight — the widget must not
    /// keep showing yesterday's consumption. It renders zero-consumed against
    /// the same goals instead. A pure function so both the widget's
    /// `TimelineProvider` and this file's tests can call it without going
    /// through `UserDefaults`.
    func displayValues(today dayKey: String) -> WidgetSnapshot {
        guard self.dayKey != dayKey else { return self }
        return WidgetSnapshot(
            dayKey: dayKey,
            kcalConsumed: 0,
            kcalGoal: kcalGoal,
            waterML: 0,
            waterGoalML: waterGoalML,
            volumeUnitRaw: volumeUnitRaw,
            generatedAt: generatedAt
        )
    }
}

/// Reads and writes ``WidgetSnapshot`` to the App Group's shared
/// `UserDefaults` suite.
enum WidgetSnapshotStore {
    /// Must match the App Group entitlement on both the app and widget
    /// extension targets.
    static let appGroupID = "group.com.yungsukuna.tally"

    private static let defaultsKey = "widgetSnapshot"

    /// `nil` if the App Group suite is unavailable — for example an unsigned
    /// CI or simulator build without the entitlement provisioned. Callers
    /// treat that the same as "no snapshot yet".
    private static var suite: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    /// Loads the last snapshot written by the app. `nil` if none has been
    /// written yet, the suite is unavailable, or the stored data is no
    /// longer decodable (for example after a format change).
    static func load() -> WidgetSnapshot? {
        guard let suite, let data = suite.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// Saves `snapshot`. A no-op if the suite is unavailable.
    static func save(_ snapshot: WidgetSnapshot) {
        guard let suite, let data = try? JSONEncoder().encode(snapshot) else { return }
        suite.set(data, forKey: defaultsKey)
    }
}
