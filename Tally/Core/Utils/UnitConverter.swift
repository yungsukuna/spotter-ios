import Foundation

/// Conversions between stored (metric) values and whatever the user prefers to
/// see.
///
/// The rule this enforces: **everything is stored metric**. Weights in
/// kilograms, volumes in millilitres, circumferences in centimetres. Nothing
/// persists a converted value, because doing so means a preference change
/// either rewrites the database or silently reinterprets old rows. Conversion
/// happens at the edges — display and input — only.
enum UnitConverter {

    // MARK: - Weight

    static let poundsPerKilogram = 2.204_622_621_848_78

    static func kilogramsToPounds(_ kg: Double) -> Double {
        kg * poundsPerKilogram
    }

    static func poundsToKilograms(_ lb: Double) -> Double {
        lb / poundsPerKilogram
    }

    /// Convert a stored kilogram value into the user's display unit.
    static func weight(_ kg: Double, in unit: WeightUnit) -> Double {
        switch unit {
        case .kilograms: kg
        case .pounds: kilogramsToPounds(kg)
        }
    }

    /// Convert a value the user typed, in their display unit, back to kilograms.
    static func weightToKilograms(_ value: Double, from unit: WeightUnit) -> Double {
        switch unit {
        case .kilograms: value
        case .pounds: poundsToKilograms(value)
        }
    }

    // MARK: - Volume

    /// US fluid ounce. Chosen over the imperial fluid ounce because the app's
    /// non-metric audience is overwhelmingly US, and the two differ by ~4%.
    static let millilitresPerFluidOunce = 29.573_529_562_5

    static func millilitresToFluidOunces(_ ml: Double) -> Double {
        ml / millilitresPerFluidOunce
    }

    static func fluidOuncesToMillilitres(_ floz: Double) -> Double {
        floz * millilitresPerFluidOunce
    }

    static func volume(_ ml: Double, in unit: VolumeUnit) -> Double {
        switch unit {
        case .millilitres: ml
        case .fluidOunces: millilitresToFluidOunces(ml)
        }
    }

    static func volumeToMillilitres(_ value: Double, from unit: VolumeUnit) -> Double {
        switch unit {
        case .millilitres: value
        case .fluidOunces: fluidOuncesToMillilitres(value)
        }
    }

    // MARK: - Distance

    static let kilometresPerMile = 1.609_344

    static func kilometresToMiles(_ km: Double) -> Double { km / kilometresPerMile }
    static func milesToKilometres(_ miles: Double) -> Double { miles * kilometresPerMile }
}

// MARK: - Formatting

/// Formats a quantity like `1.5` or `2` without trailing zeroes.
///
/// Portion quantities read badly as either "1.000 × slice" or "2.0 slices";
/// this trims to at most two decimals and drops the point entirely for whole
/// numbers.
enum QuantityFormatter {
    nonisolated(unsafe) private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private static let lock = NSLock()

    static func string(from value: Double) -> String {
        lock.lock()
        defer { lock.unlock() }
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

/// Display helpers for measured values, each rendering with the unit attached.
///
/// Named `Format` rather than the more obvious `MeasurementFormatter`, which
/// would shadow the Foundation class of that name.
enum Format {

    /// "82.5 kg" / "181.9 lb"
    static func weight(_ kg: Double, in unit: WeightUnit, includeUnit: Bool = true) -> String {
        let converted = UnitConverter.weight(kg, in: unit)
        // Half-kilo and half-pound increments are the finest anyone loads a bar
        // to, so one decimal place is the right resolution here.
        let number = String(format: "%.1f", converted)
            .replacingOccurrences(of: ".0", with: "")
        return includeUnit ? "\(number) \(unit.abbreviation)" : number
    }

    /// "250 ml" / "8.5 fl oz"
    static func volume(_ ml: Double, in unit: VolumeUnit, includeUnit: Bool = true) -> String {
        let converted = UnitConverter.volume(ml, in: unit)
        let number: String = switch unit {
        case .millilitres: String(format: "%.0f", converted)
        case .fluidOunces: String(format: "%.1f", converted)
        }
        return includeUnit ? "\(number) \(unit.abbreviation)" : number
    }

    /// "1,842 kcal". Rounds — sub-calorie precision is noise.
    static func energy(_ kcal: Double?, includeUnit: Bool = true) -> String {
        guard let kcal else { return includeUnit ? "— kcal" : "—" }
        let number = QuantityFormatter.string(from: kcal.rounded())
        return includeUnit ? "\(number) kcal" : number
    }

    /// "24.5 g", or an em dash when the value is unknown.
    static func grams(_ grams: Double?, includeUnit: Bool = true) -> String {
        guard let grams else { return includeUnit ? "— g" : "—" }
        let number = String(format: "%.1f", grams)
            .replacingOccurrences(of: ".0", with: "")
        return includeUnit ? "\(number) g" : number
    }

    /// "1:05:30" or "12:04" — used for workout duration and rest timers.
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
