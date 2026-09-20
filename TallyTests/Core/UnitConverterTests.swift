import Foundation
import Testing

@testable import Tally

@Suite("UnitConverter")
struct UnitConverterTests {

    @Test("Kilograms convert to pounds")
    func kilogramsToPounds() {
        #expect(abs(UnitConverter.kilogramsToPounds(100) - 220.462) < 0.01)
    }

    @Test("Weight round-trips through pounds without drift")
    func weightRoundTrip() {
        // The user switching units back and forth must never nudge a stored
        // value, so the conversion has to be exactly invertible.
        for kg in [0.0, 2.5, 20.0, 60.0, 102.5, 227.5] {
            let pounds = UnitConverter.weight(kg, in: .pounds)
            let back = UnitConverter.weightToKilograms(pounds, from: .pounds)
            #expect(abs(back - kg) < 0.000_001, "round trip failed for \(kg) kg")
        }
    }

    @Test("Kilogram display is a no-op")
    func kilogramsPassThrough() {
        #expect(UnitConverter.weight(82.5, in: .kilograms) == 82.5)
        #expect(UnitConverter.weightToKilograms(82.5, from: .kilograms) == 82.5)
    }

    @Test("Millilitres convert to US fluid ounces")
    func millilitresToFluidOunces() {
        // 500 ml ≈ 16.907 US fl oz.
        #expect(abs(UnitConverter.millilitresToFluidOunces(500) - 16.907) < 0.01)
    }

    @Test("Volume round-trips through fluid ounces without drift")
    func volumeRoundTrip() {
        for ml in [0.0, 250.0, 330.0, 500.0, 750.0, 2500.0] {
            let ounces = UnitConverter.volume(ml, in: .fluidOunces)
            let back = UnitConverter.volumeToMillilitres(ounces, from: .fluidOunces)
            #expect(abs(back - ml) < 0.000_001, "round trip failed for \(ml) ml")
        }
    }

    @Test("Distance round-trips through miles")
    func distanceRoundTrip() {
        for km in [0.0, 1.0, 5.0, 21.0975, 42.195] {
            let miles = UnitConverter.kilometresToMiles(km)
            #expect(abs(UnitConverter.milesToKilometres(miles) - km) < 0.000_001)
        }
    }
}

@Suite("Formatting")
struct FormattingTests {

    @Test("Whole weights drop the decimal point")
    func wholeWeightsAreClean() {
        #expect(Format.weight(100, in: .kilograms) == "100 kg")
        #expect(Format.weight(60, in: .kilograms) == "60 kg")
    }

    @Test("Half-kilo increments keep one decimal")
    func halfKilosShowADecimal() {
        #expect(Format.weight(102.5, in: .kilograms) == "102.5 kg")
    }

    @Test("Millilitres render whole, fluid ounces to one decimal")
    func volumeResolution() {
        #expect(Format.volume(250, in: .millilitres) == "250 ml")
        #expect(Format.volume(500, in: .fluidOunces) == "16.9 fl oz")
    }

    @Test("Unknown energy renders as a dash rather than zero")
    func unknownEnergyIsADash() {
        // Showing "0 kcal" for a product with no nutrition panel would be a
        // lie; the dash tells the user the data is missing.
        #expect(Format.energy(nil) == "— kcal")
        #expect(Format.energy(0) == "0 kcal")
    }

    @Test("Energy rounds to whole calories")
    func energyRounds() {
        // Asserted loosely on purpose: the grouping separator comes from the
        // current locale, so a hardcoded "1,842 kcal" would fail on a runner
        // configured for anywhere that groups with a space or a full stop.
        // (Some locales even group with a full stop, so "no decimal point" is
        // not a safe assertion either — rounding is checked by the digits.)
        let formatted = Format.energy(1841.7)
        #expect(formatted.hasSuffix(" kcal"))
        #expect(formatted.contains("842"))
    }

    @Test("Unknown macros render as a dash")
    func unknownGramsIsADash() {
        #expect(Format.grams(nil) == "— g")
        #expect(Format.grams(0) == "0 g")
    }

    @Test("Durations under an hour omit the hours component")
    func shortDurations() {
        #expect(Format.duration(90) == "1:30")
        #expect(Format.duration(0) == "0:00")
        #expect(Format.duration(59) == "0:59")
    }

    @Test("Durations over an hour include hours")
    func longDurations() {
        #expect(Format.duration(3930) == "1:05:30")
    }

    @Test("Negative durations clamp to zero")
    func negativeDurationsClamp() {
        // The rest timer counts down through zero; it must not render "-0:01".
        #expect(Format.duration(-5) == "0:00")
    }

    @Test("Quantities drop trailing zeroes")
    func quantityFormatting() {
        #expect(QuantityFormatter.string(from: 1) == "1")
        #expect(QuantityFormatter.string(from: 1.5) == "1.5")
        #expect(QuantityFormatter.string(from: 2.0) == "2")
    }
}
