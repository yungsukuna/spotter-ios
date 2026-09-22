import Foundation
import Testing

@testable import Tally

@Suite("PlateCalculator")
struct PlateCalculatorTests {

    @Test("100 kg on a 20 kg bar loads 25 and 15 per side")
    func kilogramExample() {
        let loading = PlateCalculator.perSide(target: 100, bar: 20, plates: PlateCalculator.platesKG)
        #expect(loading.plates == [25, 15])
        #expect(loading.achieved == 100)
        #expect(loading.remainder == 0)
    }

    @Test("225 lb on a 45 lb bar loads two 45s per side")
    func poundExample() {
        let loading = PlateCalculator.perSide(target: 225, bar: 45, plates: PlateCalculator.platesLB)
        #expect(loading.plates == [45, 45])
        #expect(loading.achieved == 225)
        #expect(loading.remainder == 0)
    }

    @Test("A target below the bar needs no plates")
    func targetBelowBar() {
        let loading = PlateCalculator.perSide(target: 15, bar: 20, plates: PlateCalculator.platesKG)
        #expect(loading.plates.isEmpty)
        #expect(loading.achieved == 20)
    }

    @Test("An unloadable target reports the remainder")
    func unloadableTargetReportsRemainder() {
        // (101 - 20) / 2 = 40.5 per side. Greedy gets to 40 (25 + 15), 0.5
        // short per side, 1 kg short overall — nothing in the set loads it.
        let loading = PlateCalculator.perSide(target: 101, bar: 20, plates: PlateCalculator.platesKG)
        #expect(loading.plates == [25, 15])
        #expect(loading.achieved == 100)
        #expect(abs(loading.remainder - 1) < 0.0001)
    }

    @Test("Zero and negative targets are safe")
    func zeroAndNegativeTargetsAreSafe() {
        let zero = PlateCalculator.perSide(target: 0, bar: 20, plates: PlateCalculator.platesKG)
        #expect(zero.plates.isEmpty)

        let negative = PlateCalculator.perSide(target: -50, bar: 20, plates: PlateCalculator.platesKG)
        #expect(negative.plates.isEmpty)
        #expect(negative.remainder == 0)
    }

    @Test("The default bar weight is 20 kg or 45 lb")
    func defaultBarWeight() {
        #expect(PlateCalculator.defaultBarWeightKG(for: .kilograms) == 20)
        #expect(abs(PlateCalculator.defaultBarWeightKG(for: .pounds) - UnitConverter.poundsToKilograms(45)) < 0.0001)
    }

    @Test("The smallest loadable increment is two of the lightest plate")
    func smallestIncrement() {
        #expect(PlateCalculator.smallestIncrement(for: .kilograms) == 2.5)
        #expect(PlateCalculator.smallestIncrement(for: .pounds) == 5)
    }
}
