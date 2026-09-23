import Foundation
import Testing

@testable import Spotter

@Suite("SetInputResolver")
struct SetInputResolverTests {

    // MARK: - Weight

    @Test("Typed weight in kilograms passes through unchanged")
    func typedWeightInKilograms() {
        let resolved = SetInputResolver.resolveWeightKG(text: "82.5", unit: .kilograms, placeholderKG: nil)
        #expect(resolved == 82.5)
    }

    @Test("Typed weight in pounds converts to kilograms")
    func typedWeightInPoundsConverts() {
        // 225 lb ≈ 102.06 kg — this is the exact scenario called out in the
        // spec: typing 225 in pounds mode must never store 225 kg.
        let resolved = SetInputResolver.resolveWeightKG(text: "225", unit: .pounds, placeholderKG: nil)
        #expect(abs(resolved - UnitConverter.poundsToKilograms(225)) < 0.0001)
        #expect(abs(resolved - 102.058) < 0.01)
    }

    @Test("An empty weight field falls back to the placeholder")
    func emptyWeightFallsBackToPlaceholder() {
        let resolved = SetInputResolver.resolveWeightKG(text: "", unit: .kilograms, placeholderKG: 60)
        #expect(resolved == 60)
    }

    @Test("An empty weight field with no placeholder resolves to zero")
    func emptyWeightWithNoPlaceholderIsZero() {
        let resolved = SetInputResolver.resolveWeightKG(text: "  ", unit: .kilograms, placeholderKG: nil)
        #expect(resolved == 0)
    }

    @Test("Unparsable weight text falls back to the placeholder")
    func unparsableWeightFallsBackToPlaceholder() {
        let resolved = SetInputResolver.resolveWeightKG(text: "abc", unit: .kilograms, placeholderKG: 45)
        #expect(resolved == 45)
    }

    @Test("A typed zero overrides a nonzero placeholder")
    func typedZeroOverridesPlaceholder() {
        // Typing "0" is a real, deliberate value — bodyweight work, say — and
        // must not be confused with an empty field.
        let resolved = SetInputResolver.resolveWeightKG(text: "0", unit: .kilograms, placeholderKG: 60)
        #expect(resolved == 0)
    }

    // MARK: - Reps

    @Test("Typed reps pass through unchanged")
    func typedRepsPassThrough() {
        #expect(SetInputResolver.resolveReps(text: "8", placeholderReps: nil) == 8)
    }

    @Test("An empty reps field falls back to the placeholder")
    func emptyRepsFallsBackToPlaceholder() {
        #expect(SetInputResolver.resolveReps(text: "", placeholderReps: 10) == 10)
    }

    @Test("Unparsable reps text falls back to the placeholder")
    func unparsableRepsFallsBackToPlaceholder() {
        #expect(SetInputResolver.resolveReps(text: "eight", placeholderReps: 5) == 5)
    }

    @Test("No placeholder and empty text resolves to zero reps")
    func noPlaceholderResolvesToZeroReps() {
        #expect(SetInputResolver.resolveReps(text: "", placeholderReps: nil) == 0)
    }

    // MARK: - Parsing

    @Test("A comma decimal separator is accepted")
    func commaDecimalSeparator() {
        #expect(SetInputResolver.parseWeightKG(text: "82,5", unit: .kilograms) == 82.5)
        #expect(SetInputResolver.resolveWeightKG(text: "82,5", unit: .kilograms, placeholderKG: 60) == 82.5)
    }

    @Test("Negative numbers are rejected")
    func negativeNumbersRejected() {
        #expect(SetInputResolver.parseWeightKG(text: "-5", unit: .kilograms) == nil)
        #expect(SetInputResolver.parseReps(text: "-3") == nil)
    }

    @Test("Empty text parses to nil, not zero")
    func emptyTextParsesToNil() {
        #expect(SetInputResolver.parseWeightKG(text: " ", unit: .kilograms) == nil)
        #expect(SetInputResolver.parseReps(text: "") == nil)
    }

    // MARK: - Write-through

    @Test("A changed weight is written back in kilograms")
    func changedWeightIsStored() {
        #expect(SetInputResolver.weightKGToStore(text: "62.5", unit: .kilograms, currentKG: 60) == 62.5)
    }

    @Test("Text that already matches the stored weight is not rewritten")
    func matchingWeightIsNotRewritten() {
        #expect(SetInputResolver.weightKGToStore(text: "60", unit: .kilograms, currentKG: 60) == nil)
    }

    @Test("A pounds round-trip does not drift the stored kilograms")
    func poundsRoundTripDoesNotDrift() {
        // 60 kg displays as "132.3" lb; converting that text back would store
        // 60.01 kg and beat the old 60 kg, awarding a false PR.
        let shown = Format.weight(60, in: .pounds, includeUnit: false)
        #expect(SetInputResolver.weightKGToStore(text: shown, unit: .pounds, currentKG: 60) == nil)
    }

    @Test("Unparsable text leaves the stored weight alone")
    func unparsableTextIsNotStored() {
        #expect(SetInputResolver.weightKGToStore(text: "abc", unit: .kilograms, currentKG: 60) == nil)
    }

    // MARK: - Completion

    @Test("A set needs at least one rep to be completed")
    func completionNeedsReps() {
        #expect(!SetInputResolver.canComplete(reps: 0))
        #expect(SetInputResolver.canComplete(reps: 1))
    }
}
