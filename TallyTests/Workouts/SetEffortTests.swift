import Foundation
import Testing

@testable import Tally

@Suite("SetEffort")
struct SetEffortTests {

    @Test("RIR is 10 minus RPE")
    func rirFormula() {
        #expect(SetEffort.rir(fromRPE: 8) == 2)
        #expect(SetEffort.rir(fromRPE: 10) == 0)
        #expect(SetEffort.rir(fromRPE: 6.5) == 3.5)
    }

    @Test("Display off gives no label even when an RPE is recorded")
    func displayOffGivesNoLabel() {
        #expect(SetEffort.label(rpe: 8, display: .off) == nil)
    }

    @Test("No recorded RPE gives no label regardless of display")
    func noRPEGivesNoLabel() {
        #expect(SetEffort.label(rpe: nil, display: .rpe) == nil)
        #expect(SetEffort.label(rpe: nil, display: .rir) == nil)
    }

    @Test("RPE display shows the RPE value")
    func rpeDisplayShowsRPE() {
        #expect(SetEffort.label(rpe: 8, display: .rpe) == "RPE 8")
        #expect(SetEffort.label(rpe: 6.5, display: .rpe) == "RPE 6.5")
    }

    @Test("RIR display shows the derived RIR value")
    func rirDisplayShowsRIR() {
        #expect(SetEffort.label(rpe: 8, display: .rir) == "RIR 2")
        #expect(SetEffort.label(rpe: 6.5, display: .rir) == "RIR 3.5")
    }

    @Test("The selectable menu values run 6 through 10 in half-point steps")
    func selectableValues() {
        #expect(SetEffort.selectableValues.first == 6)
        #expect(SetEffort.selectableValues.last == 10)
        #expect(SetEffort.selectableValues.count == 9)
    }
}
