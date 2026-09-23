import Foundation

/// Formats a set's rate of perceived exertion for display, as either RPE or
/// RIR, per `UserSettings.setEffortDisplay`.
///
/// `SetEntry.rpe` is always stored as RPE (1–10) regardless of the display
/// setting — RIR is derived at the view layer, never persisted separately, so
/// switching the setting never needs to touch existing data.
enum SetEffort {

    /// The values offered in the set row's effort menu: 6, 6.5, … 10.
    static let selectableValues: [Double] = stride(from: 6.0, through: 10.0, by: 0.5).map { $0 }

    /// RIR = 10 − RPE, per Decision 11 in `docs/PHASE2-PLAN.md`.
    static func rir(fromRPE rpe: Double) -> Double {
        10 - rpe
    }

    /// "RPE 8" / "RIR 2", or nil when there is nothing to show — either the
    /// display is off, or the set has no RPE recorded yet.
    static func label(rpe: Double?, display: SetEffortDisplay) -> String? {
        guard let rpe else { return nil }
        switch display {
        case .off:
            return nil
        case .rpe:
            return "RPE \(formatted(rpe))"
        case .rir:
            return "RIR \(formatted(rir(fromRPE: rpe)))"
        }
    }

    /// The bare number for one of the menu's selectable RPE values, e.g.
    /// "6", "6.5", "10" — always shown as RPE in the menu itself, regardless
    /// of the display setting, since the value being picked is always RPE.
    static func formatted(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
    }
}
