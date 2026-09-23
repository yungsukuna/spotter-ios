import Foundation

/// Per-side plate loading for a barbell target weight.
///
/// Works entirely in the **display unit** — see `perSide(target:bar:plates:)`
/// — so a pounds user gets 45/25/10 plates instead of an unhelpful 20.41 kg
/// figure. Greedy loading (heaviest plate first) is optimal for these
/// standard denominations, since every smaller plate weight divides evenly
/// enough into the next one up.
enum PlateCalculator {

    /// Standard plate set, kilograms. Decision 10 in `docs/PHASE2-PLAN.md`.
    static let platesKG: [Double] = [25, 20, 15, 10, 5, 2.5, 1.25]
    /// Standard plate set, pounds.
    static let platesLB: [Double] = [45, 35, 25, 10, 5, 2.5]

    /// The plate set to load from, in `unit`, heaviest first.
    static func plates(for unit: WeightUnit) -> [Double] {
        switch unit {
        case .kilograms: platesKG
        case .pounds: platesLB
        }
    }

    /// The bar weight assumed when `UserSettings.barbellWeightKG` is unset:
    /// 20 kg or 45 lb, per Decision 10.
    static func defaultBarWeightKG(for unit: WeightUnit) -> Double {
        switch unit {
        case .kilograms: 20
        case .pounds: UnitConverter.poundsToKilograms(45)
        }
    }

    /// The smallest amount a symmetrically-loaded bar's total weight can
    /// change by: two of the lightest available plate (one per side).
    static func smallestIncrement(for unit: WeightUnit) -> Double {
        guard let lightest = plates(for: unit).min() else { return 0 }
        return lightest * 2
    }

    /// Round `value` (already in `unit`) to the nearest weight actually
    /// loadable on a bar, i.e. the nearest multiple of
    /// `smallestIncrement(for:)`.
    static func roundToLoadable(_ value: Double, unit: WeightUnit) -> Double {
        let increment = smallestIncrement(for: unit)
        guard increment > 0 else { return value }
        return (value / increment).rounded() * increment
    }

    /// The result of loading one side of the bar.
    struct Loading: Equatable {
        /// Plates for *one side*, heaviest first.
        var plates: [Double]
        /// Total weight actually achieved (bar + both sides' plates), in the
        /// same unit as `target`.
        var achieved: Double
        /// How far `achieved` falls short of `target`. Zero when the target
        /// is exactly loadable, and also zero (never negative) when the
        /// target is at or below the bar, since the bar itself can't be
        /// lightened.
        var remainder: Double
    }

    /// Greedy per-side plate loading.
    ///
    /// - Parameters:
    ///   - target: the desired total weight, in the display unit.
    ///   - bar: the bar's own weight, in the same unit.
    ///   - plates: available plate weights, in the same unit — see
    ///     `plates(for:)`. Order doesn't matter; this sorts descending.
    static func perSide(target: Double, bar: Double, plates: [Double]) -> Loading {
        guard target > bar else {
            let achieved = max(0, bar)
            return Loading(plates: [], achieved: achieved, remainder: max(0, target - achieved))
        }

        let neededPerSide = (target - bar) / 2
        var remaining = neededPerSide
        var chosen: [Double] = []
        // A little slack so floating-point noise (e.g. 40.499999999) doesn't
        // reject a plate that should fit exactly.
        let epsilon = 0.001

        for plate in plates.sorted(by: >) where plate > 0 {
            while remaining + epsilon >= plate {
                chosen.append(plate)
                remaining -= plate
            }
        }

        let achieved = bar + 2 * chosen.reduce(0, +)
        return Loading(plates: chosen, achieved: achieved, remainder: max(0, target - achieved))
    }
}
