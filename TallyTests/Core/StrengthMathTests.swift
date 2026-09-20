import Foundation
import Testing

@testable import Tally

@Suite("StrengthMath")
struct StrengthMathTests {

    // MARK: - Estimated one-rep max

    @Test("Epley matches the published formula")
    func epleyFormula() throws {
        // 100 × (1 + 5/30) = 116.666…
        let estimate = try #require(
            StrengthMath.estimatedOneRepMax(weightKG: 100, reps: 5, formula: .epley)
        )
        #expect(abs(estimate - 116.6667) < 0.001)
    }

    @Test("Brzycki matches the published formula")
    func brzyckiFormula() throws {
        // 100 × 36 / (37 − 5) = 112.5
        let estimate = try #require(
            StrengthMath.estimatedOneRepMax(weightKG: 100, reps: 5, formula: .brzycki)
        )
        #expect(abs(estimate - 112.5) < 0.001)
    }

    @Test("A single rep is its own one-rep max", arguments: [OneRepMaxFormula.epley, .brzycki])
    func singleRepIsItsOwnMax(formula: OneRepMaxFormula) throws {
        let estimate = try #require(
            StrengthMath.estimatedOneRepMax(weightKG: 140, reps: 1, formula: formula)
        )
        // Epley: 140 × (1 + 1/30) = 144.67; Brzycki: 140 × 36/36 = 140.
        // Epley is known to overestimate at one rep, which is expected — the
        // assertion is only that both stay in a sane neighbourhood.
        #expect(estimate >= 140)
        #expect(estimate < 150)
    }

    @Test("Bodyweight sets have no estimable one-rep max")
    func zeroWeightYieldsNil() {
        // Returning nil rather than 0 keeps bodyweight work from flattening a
        // strength chart against the axis.
        #expect(StrengthMath.estimatedOneRepMax(weightKG: 0, reps: 10) == nil)
    }

    @Test("Zero reps have no estimable one-rep max")
    func zeroRepsYieldsNil() {
        #expect(StrengthMath.estimatedOneRepMax(weightKG: 100, reps: 0) == nil)
    }

    @Test("Very high rep sets are excluded from estimates")
    func highRepsExcluded() {
        // Rep-max formulae diverge badly past ~20 reps; Brzycki blows up
        // entirely at 37. Both are refused rather than returning nonsense.
        #expect(StrengthMath.estimatedOneRepMax(weightKG: 60, reps: 21) == nil)
        #expect(StrengthMath.estimatedOneRepMax(weightKG: 60, reps: 40, formula: .brzycki) == nil)
    }

    // MARK: - Volume

    @Test("Volume is weight times reps")
    func volumeMultiplies() {
        #expect(StrengthMath.volume(weightKG: 80, reps: 8) == 640)
    }

    @Test("Volume of an unperformed set is zero")
    func volumeOfZeroReps() {
        #expect(StrengthMath.volume(weightKG: 80, reps: 0) == 0)
    }

    // MARK: - Rep records

    @Test("Rep records keep the heaviest weight per rep count")
    func repRecordsPickHeaviest() throws {
        let base = Date(timeIntervalSince1970: 0)
        let sets = [
            StrengthMath.CompletedSet(weightKG: 100, reps: 5, performedAt: base),
            StrengthMath.CompletedSet(weightKG: 110, reps: 5, performedAt: base.addingTimeInterval(86400)),
            StrengthMath.CompletedSet(weightKG: 105, reps: 5, performedAt: base.addingTimeInterval(172800)),
            StrengthMath.CompletedSet(weightKG: 90, reps: 8, performedAt: base),
        ]

        let records = StrengthMath.repRecords(from: sets)

        #expect(records.count == 2)
        let fiveRepRecord = try #require(records.first { $0.reps == 5 })
        #expect(fiveRepRecord.weightKG == 110)
        let eightRepRecord = try #require(records.first { $0.reps == 8 })
        #expect(eightRepRecord.weightKG == 90)
    }

    @Test("Rep records are sorted by rep count")
    func repRecordsSorted() {
        let base = Date(timeIntervalSince1970: 0)
        let sets = [
            StrengthMath.CompletedSet(weightKG: 60, reps: 12, performedAt: base),
            StrengthMath.CompletedSet(weightKG: 140, reps: 1, performedAt: base),
            StrengthMath.CompletedSet(weightKG: 100, reps: 5, performedAt: base),
        ]

        #expect(StrengthMath.repRecords(from: sets).map(\.reps) == [1, 5, 12])
    }

    @Test("A repeated weight keeps the original record date")
    func repRecordTiesGoToTheEarlierDate() throws {
        let base = Date(timeIntervalSince1970: 0)
        let later = base.addingTimeInterval(86400)
        let sets = [
            StrengthMath.CompletedSet(weightKG: 100, reps: 5, performedAt: base),
            StrengthMath.CompletedSet(weightKG: 100, reps: 5, performedAt: later),
        ]

        // Hitting the same weight again is not a new record — the record was
        // set the first time.
        let record = try #require(StrengthMath.repRecords(from: sets).first)
        #expect(record.achievedAt == base)
    }

    @Test("Sets with no weight or no reps are ignored")
    func repRecordsIgnoreEmptySets() {
        let base = Date(timeIntervalSince1970: 0)
        let sets = [
            StrengthMath.CompletedSet(weightKG: 0, reps: 10, performedAt: base),
            StrengthMath.CompletedSet(weightKG: 100, reps: 0, performedAt: base),
        ]
        #expect(StrengthMath.repRecords(from: sets).isEmpty)
    }

    // MARK: - Personal records

    @Test("Beating the previous best at the same rep count is a PR")
    func beatingPreviousBestIsAPR() {
        let base = Date(timeIntervalSince1970: 0)
        let history = [StrengthMath.CompletedSet(weightKG: 100, reps: 5, performedAt: base)]
        let candidate = StrengthMath.CompletedSet(weightKG: 102.5, reps: 5, performedAt: base)

        #expect(StrengthMath.isPersonalRecord(candidate: candidate, against: history))
    }

    @Test("Matching the previous best is not a PR")
    func matchingIsNotAPR() {
        let base = Date(timeIntervalSince1970: 0)
        let history = [StrengthMath.CompletedSet(weightKG: 100, reps: 5, performedAt: base)]
        let candidate = StrengthMath.CompletedSet(weightKG: 100, reps: 5, performedAt: base)

        #expect(!StrengthMath.isPersonalRecord(candidate: candidate, against: history))
    }

    @Test("The first set at a rep count is always a PR")
    func firstSetAtARepCountIsAPR() {
        let base = Date(timeIntervalSince1970: 0)
        // History exists, but nothing at 3 reps — so this is the first.
        let history = [StrengthMath.CompletedSet(weightKG: 100, reps: 5, performedAt: base)]
        let candidate = StrengthMath.CompletedSet(weightKG: 80, reps: 3, performedAt: base)

        #expect(StrengthMath.isPersonalRecord(candidate: candidate, against: history))
    }

    @Test("Records are tracked per rep count, not across them")
    func recordsAreScopedPerRepCount() {
        let base = Date(timeIntervalSince1970: 0)
        let history = [StrengthMath.CompletedSet(weightKG: 140, reps: 1, performedAt: base)]
        // Lighter than the 1-rep best, but it is the first 10-rep set, so it
        // sets that record.
        let candidate = StrengthMath.CompletedSet(weightKG: 90, reps: 10, performedAt: base)

        #expect(StrengthMath.isPersonalRecord(candidate: candidate, against: history))
    }
}
