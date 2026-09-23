import SwiftUI

/// Design tokens.
///
/// Colours are defined against the system semantic palette rather than as fixed
/// hex values, so dark mode, increased contrast and Dynamic Type all work
/// without a second set of definitions to keep in sync.
enum Theme {

    // MARK: - Colour

    enum Colors {
        /// Brand accent. Also set as the asset-catalogue accent colour so
        /// system controls pick it up.
        static let accent = Color.accentColor

        /// Per-domain tints. Each section of the app has one so a glance at a
        /// chart or a ring tells you what it is measuring.
        static let nutrition = Color.orange
        static let water = Color.blue
        static let workout = Color.purple

        /// Macro colours, used consistently across rings, bars and legends.
        static let protein = Color.red
        static let carbs = Color.yellow
        static let fat = Color.teal

        static let success = Color.green
        static let warning = Color.orange
        static let danger = Color.red

        /// Personal-record highlight on the logging screen.
        static let personalRecord = Color.yellow

        static let primaryText = Color.primary
        static let secondaryText = Color.secondary
        static let tertiaryText = Color(uiColor: .tertiaryLabel)

        static let groupedBackground = Color(uiColor: .systemGroupedBackground)
        static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
        static let separator = Color(uiColor: .separator)

        /// Fill behind an uncompleted set row.
        static let setRowPending = Color(uiColor: .tertiarySystemFill)
        /// Fill behind a completed set row.
        static let setRowCompleted = Color.green.opacity(0.14)
    }

    // MARK: - Spacing

    /// A 4-point scale. Use these rather than literals so density stays
    /// consistent between screens built by different people.
    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: - Shape

    enum Radius {
        static let sm: CGFloat = 6
        static let md: CGFloat = 10
        static let lg: CGFloat = 16
        static let pill: CGFloat = 999
    }

    // MARK: - Typography

    /// Always relative to a system text style, never a fixed point size, so
    /// Dynamic Type scales the whole app.
    enum Typography {
        /// Large numeric readouts: day totals, the rest timer.
        static let metric = Font.system(.largeTitle, design: .rounded, weight: .bold)
        /// Medium numerics: card headline figures.
        static let metricSmall = Font.system(.title2, design: .rounded, weight: .semibold)
        /// Numbers inside a set row. Monospaced digits stop the row jittering
        /// as the value changes.
        static let setValue = Font.system(.body, design: .rounded, weight: .medium)
            .monospacedDigit()
        static let sectionHeader = Font.subheadline.weight(.semibold)
        static let cardTitle = Font.headline
        static let caption = Font.caption
    }

    // MARK: - Layout

    enum Layout {
        /// Minimum tap target. Set rows in particular must clear this — they
        /// are tapped repeatedly, often mid-set with shaky hands.
        static let minimumTapTarget: CGFloat = 44
        static let cardPadding: CGFloat = Spacing.lg
    }
}

// MARK: - Shared modifiers

extension View {
    /// Standard card treatment: padded, filled, rounded.
    func spotterCard(padding: CGFloat = Theme.Layout.cardPadding) -> some View {
        self
            .padding(padding)
            .background(Theme.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
    }

    /// Applies a tint only when `condition` holds, for conditional emphasis.
    @ViewBuilder
    func tinted(_ color: Color, when condition: Bool) -> some View {
        if condition { self.foregroundStyle(color) } else { self }
    }
}
