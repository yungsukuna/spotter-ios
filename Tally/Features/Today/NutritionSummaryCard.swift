import SwiftData
import SwiftUI

/// Dashboard card: today's calories and macros against goal.
///
/// Reads `DiaryEntry` directly rather than going through the Nutrition tab's
/// own view types, which belong to a different workstream — this card is
/// self-contained on purpose.
struct NutritionSummaryCard: View {
    @Query private var todayEntries: [DiaryEntry]

    let goal: Nutrients

    init(goal: Nutrients, calendar: Calendar = .current) {
        self.goal = goal
        let todayKey = DayKey.today(calendar: calendar)
        _todayEntries = Query(filter: #Predicate<DiaryEntry> { $0.dayKey == todayKey })
    }

    private var summary: DashboardAggregation.NutritionSummary {
        DashboardAggregation.nutritionSummary(entries: todayEntries.map(\.nutrients), goal: goal)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Label("Nutrition", systemImage: "fork.knife")
                    .font(Theme.Typography.sectionHeader)
                    .foregroundStyle(Theme.Colors.nutrition)
                Spacer()
                Text("\(Format.energy(summary.consumed.effectiveKcal, includeUnit: false)) / \(Format.energy(goal.kcal, includeUnit: false)) kcal")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }

            if todayEntries.isEmpty {
                Text("Nothing logged yet today.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
            } else {
                MacroProgressBar(
                    title: "Protein",
                    color: Theme.Colors.protein,
                    consumed: summary.consumed.proteinG,
                    goal: goal.proteinG,
                    fraction: summary.macroFraction(\.proteinG)
                )
                MacroProgressBar(
                    title: "Carbs",
                    color: Theme.Colors.carbs,
                    consumed: summary.consumed.carbsG,
                    goal: goal.carbsG,
                    fraction: summary.macroFraction(\.carbsG)
                )
                MacroProgressBar(
                    title: "Fat",
                    color: Theme.Colors.fat,
                    consumed: summary.consumed.fatG,
                    goal: goal.fatG,
                    fraction: summary.macroFraction(\.fatG)
                )
            }
        }
        .tallyCard()
    }
}

/// A single macro's progress bar: label, grams-vs-goal, and a filled capsule.
private struct MacroProgressBar: View {
    let title: String
    let color: Color
    let consumed: Double?
    let goal: Double?
    let fraction: Double

    private var clampedFraction: Double { min(max(fraction, 0), 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            HStack {
                Text(title)
                    .font(Theme.Typography.caption)
                Spacer()
                Text("\(Format.grams(consumed, includeUnit: false))/\(Format.grams(goal, includeUnit: false)) g")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.15))
                    Capsule().fill(color).frame(width: proxy.size.width * clampedFraction)
                }
            }
            .frame(height: 6)
        }
    }
}

#Preview {
    NutritionSummaryCard(goal: Nutrients(kcal: 2000, proteinG: 150, carbsG: 200, fatG: 67))
        .padding()
        .modelContainer(TallySchema.previewContainer())
}
