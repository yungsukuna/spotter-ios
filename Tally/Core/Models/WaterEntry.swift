import Foundation
import SwiftData

/// One drink, logged manually.
///
/// Volume is always stored in millilitres and converted for display, so
/// switching units in Settings never rewrites stored data or loses precision on
/// round-tripping.
@Model
final class WaterEntry {
    var id: UUID = UUID()
    var loggedAt: Date = Date()
    /// `yyyy-MM-dd`, see the note on `DiaryEntry.dayKey`.
    var dayKey: String = ""
    var volumeML: Double = 0
    /// Which quick-add button produced this, e.g. "Glass". Nil for custom amounts.
    var presetLabel: String?

    init(
        id: UUID = UUID(),
        loggedAt: Date = Date(),
        volumeML: Double,
        presetLabel: String? = nil,
        calendar: Calendar = .current
    ) {
        self.id = id
        self.loggedAt = loggedAt
        self.dayKey = DayKey.make(from: loggedAt, calendar: calendar)
        self.volumeML = volumeML
        self.presetLabel = presetLabel
    }

    func updateLoggedAt(_ date: Date, calendar: Calendar = .current) {
        loggedAt = date
        dayKey = DayKey.make(from: date, calendar: calendar)
    }
}

/// A quick-add button on the water screen.
struct WaterPreset: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var label: String
    var volumeML: Double
    /// SF Symbol shown on the button.
    var symbolName: String

    init(id: UUID = UUID(), label: String, volumeML: Double, symbolName: String) {
        self.id = id
        self.label = label
        self.volumeML = volumeML
        self.symbolName = symbolName
    }

    /// Defaults seeded on first launch. Metric, matching the app's default units.
    static let defaults: [WaterPreset] = [
        WaterPreset(label: "Glass", volumeML: 250, symbolName: "cup.and.saucer"),
        WaterPreset(label: "Bottle", volumeML: 500, symbolName: "waterbottle"),
        WaterPreset(label: "Large bottle", volumeML: 750, symbolName: "waterbottle.fill"),
        WaterPreset(label: "Mug", volumeML: 350, symbolName: "mug"),
    ]
}
