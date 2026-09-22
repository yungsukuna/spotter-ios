import Foundation
import Testing

@testable import Tally

@Suite("GoalCalculator")
struct GoalCalculatorTests {

    private func baseInput(
        weightKG: Double = 80,
        heightCM: Double = 180,
        birthYear: Int = 1995,
        sex: BiologicalSex? = .male,
        activityLevel: ActivityLevel = .sedentary,
        weightGoal: WeightGoal = .maintain,
        weeklyRateKG: Double = 0,
        proteinGPerKG: Double = 1.6,
        currentYear: Int = 2025
    ) -> GoalCalculator.Input {
        GoalCalculator.Input(
            weightKG: weightKG,
            heightCM: heightCM,
            birthYear: birthYear,
            sex: sex,
            activityLevel: activityLevel,
            weightGoal: weightGoal,
            weeklyRateKG: weeklyRateKG,
            proteinGPerKG: proteinGPerKG,
            currentYear: currentYear
        )
    }

    // MARK: - BMR

    @Test("Male, 80 kg, 180 cm, age 30 gives BMR 1780")
    func maleBMR() {
        let bmr = GoalCalculator.bmr(weightKG: 80, heightCM: 180, age: 30, sex: .male)
        #expect(bmr == 1780)
    }

    @Test("Female, 80 kg, 180 cm, age 30 gives BMR 1614")
    func femaleBMR() {
        let bmr = GoalCalculator.bmr(weightKG: 80, heightCM: 180, age: 30, sex: .female)
        #expect(bmr == 1614)
    }

    @Test("Unspecified sex uses the midpoint constant, giving BMR 1697")
    func unspecifiedBMR() {
        // Mifflin-St Jeor base (10·80 + 6.25·180 − 5·30) is 1775. The
        // unspecified constant is the midpoint of +5 (male) and −161
        // (female), which is −78, giving 1775 − 78 = 1697.
        let bmr = GoalCalculator.bmr(weightKG: 80, heightCM: 180, age: 30, sex: nil)
        #expect(bmr == 1697)
    }

    // MARK: - Age

    @Test("Age derives from birth year against an injected current year")
    func ageFromBirthYear() {
        #expect(GoalCalculator.age(birthYear: 1995, currentYear: 2025) == 30)
        #expect(GoalCalculator.age(birthYear: 2025, currentYear: 2025) == 0)
    }

    @Test("Age never goes negative for a birth year after the current year")
    func ageNeverNegative() {
        #expect(GoalCalculator.age(birthYear: 2030, currentYear: 2025) == 0)
    }

    // MARK: - TDEE multipliers

    @Test("Each activity level applies its multiplier to the BMR")
    func multipliersApplyCorrectly() {
        let bmr = 1780.0
        let expected: [ActivityLevel: Double] = [
            .sedentary: 1.2,
            .light: 1.375,
            .moderate: 1.55,
            .veryActive: 1.725,
            .extraActive: 1.9,
        ]
        for (level, multiplier) in expected {
            let tdee = GoalCalculator.maintenanceKcal(bmr: bmr, activityLevel: level)
            #expect(abs(tdee - bmr * multiplier) < 0.0001)
        }
    }

    // MARK: - Goal adjustment

    @Test("Losing 0.5 kg/wk gives a −550 kcal/day adjustment")
    func losingHalfKgPerWeek() {
        let adjustment = GoalCalculator.goalAdjustmentKcal(weightGoal: .lose, weeklyRateKG: 0.5)
        #expect(abs(adjustment - (-550)) < 0.0001)
    }

    @Test("Gaining 0.5 kg/wk gives a +550 kcal/day adjustment")
    func gainingHalfKgPerWeek() {
        let adjustment = GoalCalculator.goalAdjustmentKcal(weightGoal: .gain, weeklyRateKG: 0.5)
        #expect(abs(adjustment - 550) < 0.0001)
    }

    @Test("Maintaining ignores the weekly rate entirely")
    func maintainingIgnoresRate() {
        let adjustment = GoalCalculator.goalAdjustmentKcal(weightGoal: .maintain, weeklyRateKG: 1.0)
        #expect(adjustment == 0)
    }

    // MARK: - Floor clamp

    @Test("An aggressive cut is clamped to the BMR/1200 floor")
    func floorClampApplies() {
        // A light, sedentary person losing an aggressive 2 kg/wk would fall
        // well under both their BMR and the 1200 kcal absolute floor.
        let input = baseInput(
            weightKG: 50,
            heightCM: 150,
            activityLevel: .sedentary,
            weightGoal: .lose,
            weeklyRateKG: 2.0
        )
        let result = GoalCalculator.calculate(input)

        #expect(result.isClamped)
        #expect(result.targetKcal >= result.bmr)
        #expect(result.targetKcal >= 1200)
    }

    @Test("A moderate goal is not clamped")
    func moderateGoalNotClamped() {
        let input = baseInput(activityLevel: .moderate, weightGoal: .lose, weeklyRateKG: 0.5)
        let result = GoalCalculator.calculate(input)
        #expect(!result.isClamped)
    }

    // MARK: - Macros

    @Test("Carbs never go negative even when protein and fat exceed the target")
    func carbsNeverNegative() {
        // A heavy person on a high-protein cut: protein (2.4 g/kg × 150 kg)
        // plus the 0.8 g/kg fat baseline together exceed the clamped
        // calorie target, so the remaining-kcal-for-carbs term would
        // otherwise go negative.
        let input = baseInput(
            weightKG: 150,
            heightCM: 150,
            activityLevel: .sedentary,
            weightGoal: .lose,
            weeklyRateKG: 2.0,
            proteinGPerKG: 2.4
        )
        let result = GoalCalculator.calculate(input)
        #expect(result.carbsG == 0)
    }

    @Test("Protein is proportional to g/kg times body weight")
    func proteinIsGramsPerKilogram() {
        let input = baseInput(weightKG: 80, proteinGPerKG: 1.6)
        let result = GoalCalculator.calculate(input)
        #expect(abs(result.proteinG - 128) < 1)
    }

    @Test("Fat never falls below 20% of the target's kcal")
    func fatFloorsAtTwentyPercentOfKcal() {
        // A light person eating very little protein would otherwise let the
        // 0.8 g/kg baseline fat come in under 20% of a small target.
        let input = baseInput(weightKG: 45, heightCM: 150, activityLevel: .sedentary, proteinGPerKG: 1.2)
        let result = GoalCalculator.calculate(input)
        let fatKcal = result.fatG * 9
        #expect(fatKcal >= result.targetKcal * 0.2 - 9) // within one gram's rounding
    }

    @Test("The target calorie figure rounds to the nearest 10")
    func targetRoundsToNearestTen() {
        let input = baseInput(activityLevel: .light, weightGoal: .maintain)
        let result = GoalCalculator.calculate(input)
        #expect(result.targetKcal.truncatingRemainder(dividingBy: 10) == 0)
    }

    // MARK: - Full calculation sanity

    @Test("A maintain goal's target equals the rounded maintenance kcal")
    func maintainTargetMatchesMaintenance() {
        let input = baseInput(activityLevel: .moderate, weightGoal: .maintain)
        let result = GoalCalculator.calculate(input)
        let roundedMaintenance = (result.maintenanceKcal / 10).rounded() * 10
        #expect(result.targetKcal == roundedMaintenance)
    }
}
