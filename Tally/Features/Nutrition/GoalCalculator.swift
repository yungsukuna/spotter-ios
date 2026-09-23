import Foundation

/// Turns body stats into calorie and macro targets.
///
/// Pure and container-free, following the pattern in `BodyWeightTrend`: the
/// view collects inputs (prefilled from `BodyWeightTrend.latestTrendKG` where
/// possible) and this type does the maths, so it is testable without SwiftUI
/// or SwiftData and the "now" used for age can be injected.
///
/// This is an estimate, not medical advice — `GoalCalculatorView` carries that
/// disclaimer alongside the result.
enum GoalCalculator {

    /// Everything the calculator needs. `weeklyRateKG` is ignored (treated as
    /// zero) when `weightGoal` is `.maintain`.
    struct Input: Sendable {
        var weightKG: Double
        var heightCM: Double
        var birthYear: Int
        /// Nil is "prefer not to say", which uses the midpoint constant.
        var sex: BiologicalSex?
        var activityLevel: ActivityLevel
        var weightGoal: WeightGoal
        /// kg/week. Sign is ignored — direction comes from `weightGoal`.
        var weeklyRateKG: Double
        var proteinGPerKG: Double
        /// The year "now" falls in, so age can be computed deterministically
        /// in tests instead of depending on the clock.
        var currentYear: Int

        init(
            weightKG: Double,
            heightCM: Double,
            birthYear: Int,
            sex: BiologicalSex?,
            activityLevel: ActivityLevel,
            weightGoal: WeightGoal,
            weeklyRateKG: Double,
            proteinGPerKG: Double,
            currentYear: Int = Calendar.current.component(.year, from: Date())
        ) {
            self.weightKG = weightKG
            self.heightCM = heightCM
            self.birthYear = birthYear
            self.sex = sex
            self.activityLevel = activityLevel
            self.weightGoal = weightGoal
            self.weeklyRateKG = weeklyRateKG
            self.proteinGPerKG = proteinGPerKG
            self.currentYear = currentYear
        }
    }

    /// The computed result. Calorie figures are kcal/day.
    struct Result: Sendable, Hashable {
        /// Mifflin–St Jeor basal metabolic rate, unrounded.
        var bmr: Double
        /// `bmr × activityLevel.multiplier`, unrounded.
        var maintenanceKcal: Double
        /// The final daily calorie target, rounded to the nearest 10.
        var targetKcal: Double
        /// True when `maintenanceKcal + adjustment` fell below the floor and
        /// was raised to it. The view surfaces this as a note.
        var isClamped: Bool
        /// Grams/day, rounded to whole numbers.
        var proteinG: Double
        var fatG: Double
        var carbsG: Double
    }

    /// `s` in the Mifflin–St Jeor formula. Unspecified sex uses the midpoint
    /// of the male and female constants, rather than assuming either.
    private static func sexConstant(_ sex: BiologicalSex?) -> Double {
        switch sex {
        case .male: 5
        case .female: -161
        case nil: -78
        }
    }

    /// Fat is never below 20% of the day's kcal, expressed in grams.
    private static let minimumFatFractionOfKcal = 0.2
    private static let gramsPerKcalFat = 9.0
    private static let gramsPerKcalCarb = 4.0
    private static let gramsPerKcalProtein = 4.0
    /// A commonly used kcal-per-kg energy density for body fat, used to turn
    /// a weekly rate of change into a daily calorie adjustment.
    private static let kcalPerKGBodyChange = 7700.0
    /// The daily target is never allowed below this floor, even for an
    /// aggressive cut, per the plan's clamp rule.
    private static let absoluteFloorKcal = 1200.0

    /// Age in whole years, from a birth year against `currentYear`. Never
    /// negative — a `birthYear` after `currentYear` (bad input) clamps to 0
    /// rather than producing a negative age that would inflate the BMR.
    static func age(birthYear: Int, currentYear: Int) -> Int {
        max(0, currentYear - birthYear)
    }

    /// Mifflin–St Jeor: `10·kg + 6.25·cm − 5·age + s`.
    static func bmr(weightKG: Double, heightCM: Double, age: Int, sex: BiologicalSex?) -> Double {
        10 * weightKG + 6.25 * heightCM - 5 * Double(age) + sexConstant(sex)
    }

    /// TDEE: BMR scaled by the activity multiplier.
    static func maintenanceKcal(bmr: Double, activityLevel: ActivityLevel) -> Double {
        bmr * activityLevel.multiplier
    }

    /// Daily kcal adjustment for the goal: negative to lose, positive to
    /// gain, zero to maintain. Magnitude is `rate × 7700 ÷ 7`.
    static func goalAdjustmentKcal(weightGoal: WeightGoal, weeklyRateKG: Double) -> Double {
        let magnitude = abs(weeklyRateKG) * kcalPerKGBodyChange / 7
        switch weightGoal {
        case .maintain: return 0
        case .lose: return -magnitude
        case .gain: return magnitude
        }
    }

    /// Runs the full calculation described in the Phase 2 plan:
    /// BMR → TDEE → goal adjustment → floor clamp → rounded target → macros.
    static func calculate(_ input: Input) -> Result {
        let years = age(birthYear: input.birthYear, currentYear: input.currentYear)
        let bmrValue = bmr(weightKG: input.weightKG, heightCM: input.heightCM, age: years, sex: input.sex)
        let maintenance = maintenanceKcal(bmr: bmrValue, activityLevel: input.activityLevel)
        let adjustment = goalAdjustmentKcal(weightGoal: input.weightGoal, weeklyRateKG: input.weeklyRateKG)

        let rawTarget = maintenance + adjustment
        let floorKcal = max(bmrValue, absoluteFloorKcal)
        let isClamped = rawTarget < floorKcal
        // Rounding to the nearest 10 can round *down*, which would put a
        // clamped target back under its own floor. Round up instead when
        // clamped, so `targetKcal >= floorKcal` always holds.
        let targetKcal = isClamped
            ? (floorKcal / 10).rounded(.up) * 10
            : (rawTarget / 10).rounded() * 10

        let proteinG = input.proteinGPerKG * input.weightKG
        let proteinKcal = proteinG * gramsPerKcalProtein

        // Fat floors at 20% of the day's kcal, expressed in grams; the
        // 0.8 g/kg baseline can only push it higher.
        let baselineFatG = 0.8 * input.weightKG
        let minimumFatG = (minimumFatFractionOfKcal * targetKcal) / gramsPerKcalFat
        let fatG = max(baselineFatG, minimumFatG)
        let fatKcal = fatG * gramsPerKcalFat

        let remainingKcal = max(0, targetKcal - proteinKcal - fatKcal)
        let carbsG = remainingKcal / gramsPerKcalCarb

        return Result(
            bmr: bmrValue,
            maintenanceKcal: maintenance,
            targetKcal: targetKcal,
            isClamped: isClamped,
            proteinG: proteinG.rounded(),
            fatG: fatG.rounded(),
            carbsG: carbsG.rounded()
        )
    }
}
