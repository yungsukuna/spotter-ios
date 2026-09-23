import Foundation
import Testing

@testable import Tally

@Suite("RestDuration")
struct RestDurationTests {

    @Test("An exercise override wins over the global default")
    func overrideWins() {
        let duration = RestDuration.resolve(exerciseOverride: 45, globalDefault: 90, autoStart: true)
        #expect(duration == 45)
    }

    @Test("Nil override falls back to the global default")
    func nilFallsBackToDefault() {
        let duration = RestDuration.resolve(exerciseOverride: nil, globalDefault: 90, autoStart: true)
        #expect(duration == 90)
    }

    @Test("A zero override disables the timer even when the global default is non-zero")
    func zeroDisables() {
        let duration = RestDuration.resolve(exerciseOverride: 0, globalDefault: 90, autoStart: true)
        #expect(duration == nil)
    }

    @Test("Auto-start off gives nil regardless of the durations")
    func autoStartFalseGivesNil() {
        #expect(RestDuration.resolve(exerciseOverride: 45, globalDefault: 90, autoStart: false) == nil)
        #expect(RestDuration.resolve(exerciseOverride: nil, globalDefault: 90, autoStart: false) == nil)
    }
}
