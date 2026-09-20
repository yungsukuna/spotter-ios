import SwiftUI

/// The prominent fill indicator on the Water screen: a ring that fills as the
/// day's total approaches the goal.
///
/// `fraction` may exceed 1 (the user drank past their goal) or be negative in
/// theory; the fill itself is always clamped to a full circle, since a ring
/// that overshoots its own track has nowhere to go.
struct WaterProgressRing: View {
    var fraction: Double
    var lineWidth: CGFloat = 14

    private var clampedFraction: Double {
        min(max(fraction, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.Colors.water.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clampedFraction)
                .stroke(Theme.Colors.water, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.3), value: clampedFraction)
        }
    }
}

#Preview {
    HStack(spacing: Theme.Spacing.lg) {
        WaterProgressRing(fraction: 0.3)
        WaterProgressRing(fraction: 0.85)
        WaterProgressRing(fraction: 1.3)
    }
    .frame(height: 120)
    .padding()
}
