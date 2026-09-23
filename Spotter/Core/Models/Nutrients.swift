import Foundation

/// A nutrition panel.
///
/// Two different things in this app are shaped like a nutrition panel: what a
/// food contains per 100 g, and what a logged portion actually contributed to a
/// day's totals. Both use this type; ``scaled(byGrams:)`` converts between them.
///
/// Everything except the big four is optional, and that is deliberate — Open
/// Food Facts is crowd-sourced and partial records are the norm rather than the
/// error case. A product with a calorie count but no fibre figure is still worth
/// showing, so `nil` here means "not known", never "zero".
struct Nutrients: Codable, Hashable, Sendable {
    /// Kilocalories. `nil` when the source has no energy value at all, which
    /// happens often enough on Open Food Facts that callers must handle it.
    var kcal: Double?
    var proteinG: Double?
    var carbsG: Double?
    var fatG: Double?

    var satFatG: Double?
    var sugarG: Double?
    var fiberG: Double?
    var sodiumMG: Double?

    init(
        kcal: Double? = nil,
        proteinG: Double? = nil,
        carbsG: Double? = nil,
        fatG: Double? = nil,
        satFatG: Double? = nil,
        sugarG: Double? = nil,
        fiberG: Double? = nil,
        sodiumMG: Double? = nil
    ) {
        self.kcal = kcal
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.satFatG = satFatG
        self.sugarG = sugarG
        self.fiberG = fiberG
        self.sodiumMG = sodiumMG
    }

    static let empty = Nutrients()

    /// True when none of the four headline values are known. The UI uses this to
    /// offer manual entry instead of rendering a panel of blanks.
    var isEmpty: Bool {
        kcal == nil && proteinG == nil && carbsG == nil && fatG == nil
    }

    /// True when we have enough to be worth logging at all.
    var hasEnergy: Bool { kcal != nil }

    // MARK: - Scaling

    /// Scale a per-100 g panel to an arbitrary gram weight.
    ///
    /// Unknown values stay unknown: scaling `nil` by any factor is still `nil`,
    /// not `0`. Silently treating missing fibre as zero would quietly corrupt
    /// daily totals, so it is not done here.
    func scaled(byGrams grams: Double) -> Nutrients {
        scaled(by: grams / 100.0)
    }

    /// Multiply every known value by `factor`.
    func scaled(by factor: Double) -> Nutrients {
        guard factor.isFinite else { return .empty }
        return Nutrients(
            kcal: kcal.map { $0 * factor },
            proteinG: proteinG.map { $0 * factor },
            carbsG: carbsG.map { $0 * factor },
            fatG: fatG.map { $0 * factor },
            satFatG: satFatG.map { $0 * factor },
            sugarG: sugarG.map { $0 * factor },
            fiberG: fiberG.map { $0 * factor },
            sodiumMG: sodiumMG.map { $0 * factor }
        )
    }

    // MARK: - Aggregation

    /// Add two panels, treating unknown as zero *for the purpose of summing*.
    ///
    /// This differs from ``scaled(by:)`` on purpose. When totalling a day, a
    /// food with no fibre figure should contribute nothing to the fibre total
    /// rather than poisoning it to `nil` — but a value stays `nil` only if
    /// *neither* side knew it, so "no data at all" is still distinguishable
    /// from "genuinely zero".
    static func + (lhs: Nutrients, rhs: Nutrients) -> Nutrients {
        func add(_ a: Double?, _ b: Double?) -> Double? {
            guard a != nil || b != nil else { return nil }
            return (a ?? 0) + (b ?? 0)
        }
        return Nutrients(
            kcal: add(lhs.kcal, rhs.kcal),
            proteinG: add(lhs.proteinG, rhs.proteinG),
            carbsG: add(lhs.carbsG, rhs.carbsG),
            fatG: add(lhs.fatG, rhs.fatG),
            satFatG: add(lhs.satFatG, rhs.satFatG),
            sugarG: add(lhs.sugarG, rhs.sugarG),
            fiberG: add(lhs.fiberG, rhs.fiberG),
            sodiumMG: add(lhs.sodiumMG, rhs.sodiumMG)
        )
    }

    static func += (lhs: inout Nutrients, rhs: Nutrients) {
        lhs = lhs + rhs
    }

    /// Sum a sequence of panels. Empty sequence yields ``empty``.
    static func total(of panels: some Sequence<Nutrients>) -> Nutrients {
        panels.reduce(.empty, +)
    }

    // MARK: - Derived

    /// Energy implied by the macros, using Atwater factors (4/4/9 kcal per gram).
    ///
    /// Useful as a fallback when a source gives macros but no calorie figure,
    /// and as a sanity check when it gives both.
    var kcalFromMacros: Double? {
        guard proteinG != nil || carbsG != nil || fatG != nil else { return nil }
        return (proteinG ?? 0) * 4 + (carbsG ?? 0) * 4 + (fatG ?? 0) * 9
    }

    /// ``kcal`` if known, otherwise the Atwater estimate from the macros.
    var effectiveKcal: Double? { kcal ?? kcalFromMacros }
}
