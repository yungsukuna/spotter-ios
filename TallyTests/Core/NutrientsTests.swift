import Foundation
import Testing

@testable import Tally

@Suite("Nutrients")
struct NutrientsTests {

    @Test("Scaling by grams divides by 100")
    func scalingByGrams() {
        let per100g = Nutrients(kcal: 400, proteinG: 20, carbsG: 50, fatG: 10)
        let half = per100g.scaled(byGrams: 50)

        #expect(half.kcal == 200)
        #expect(half.proteinG == 10)
        #expect(half.carbsG == 25)
        #expect(half.fatG == 5)
    }

    @Test("Scaling preserves unknown values as unknown, not zero")
    func scalingPreservesNil() {
        // The distinction matters: a product with no fibre figure must not
        // start claiming it contains zero fibre once a portion is logged.
        let partial = Nutrients(kcal: 100, proteinG: nil, carbsG: 10, fatG: nil)
        let scaled = partial.scaled(byGrams: 200)

        #expect(scaled.kcal == 200)
        #expect(scaled.proteinG == nil)
        #expect(scaled.carbsG == 20)
        #expect(scaled.fatG == nil)
    }

    @Test("Scaling by a non-finite factor yields empty rather than NaN")
    func scalingGuardsAgainstNonFinite() {
        let per100g = Nutrients(kcal: 400)
        // A zero-gram serving would otherwise produce a NaN factor and poison
        // every downstream total.
        let scaled = per100g.scaled(by: .nan)
        #expect(scaled.isEmpty)
    }

    @Test("Addition treats unknown as zero when the other side knows")
    func additionMixesKnownAndUnknown() {
        let a = Nutrients(kcal: 100, proteinG: 10, fiberG: 3)
        let b = Nutrients(kcal: 50, proteinG: nil, fiberG: nil)
        let total = a + b

        #expect(total.kcal == 150)
        #expect(total.proteinG == 10)
        #expect(total.fiberG == 3)
    }

    @Test("Addition keeps a value unknown only when neither side knows it")
    func additionPreservesTotalIgnorance() {
        let a = Nutrients(kcal: 100)
        let b = Nutrients(kcal: 50)
        let total = a + b

        #expect(total.kcal == 150)
        // Neither side had a sugar figure, so the total genuinely has none.
        #expect(total.sugarG == nil)
    }

    @Test("Totalling an empty sequence is empty")
    func totalOfNothing() {
        #expect(Nutrients.total(of: [Nutrients]()).isEmpty)
    }

    @Test("Totalling sums every panel")
    func totalOfSeveral() {
        let panels = [
            Nutrients(kcal: 100, proteinG: 5),
            Nutrients(kcal: 250, proteinG: 30),
            Nutrients(kcal: 75, proteinG: 2),
        ]
        let total = Nutrients.total(of: panels)

        #expect(total.kcal == 425)
        #expect(total.proteinG == 37)
    }

    @Test("Atwater estimate uses 4/4/9")
    func atwaterEstimate() {
        let macros = Nutrients(proteinG: 10, carbsG: 20, fatG: 5)
        // 10·4 + 20·4 + 5·9 = 165
        #expect(macros.kcalFromMacros == 165)
    }

    @Test("Effective kcal prefers the stated value over the estimate")
    func effectiveKcalPrefersStated() {
        // Real panels rarely match Atwater exactly; the label wins.
        let stated = Nutrients(kcal: 150, proteinG: 10, carbsG: 20, fatG: 5)
        #expect(stated.effectiveKcal == 150)
    }

    @Test("Effective kcal falls back to the macro estimate")
    func effectiveKcalFallsBack() {
        let noEnergy = Nutrients(proteinG: 10, carbsG: 20, fatG: 5)
        #expect(noEnergy.effectiveKcal == 165)
    }

    @Test("Effective kcal is unknown when there is nothing to work from")
    func effectiveKcalUnknown() {
        #expect(Nutrients.empty.effectiveKcal == nil)
    }

    @Test("A panel of only zeroes is not empty")
    func zeroIsNotEmpty() {
        // Sparkling water genuinely has zero calories. That is data, not the
        // absence of data, and the UI must show it rather than prompting for
        // manual entry.
        let water = Nutrients(kcal: 0, proteinG: 0, carbsG: 0, fatG: 0)
        #expect(!water.isEmpty)
        #expect(water.hasEnergy)
    }
}
