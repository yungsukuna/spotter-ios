import ActivityKit
import SwiftUI
import WidgetKit

/// Lock Screen banner and Dynamic Island presentation for the rest-timer
/// Live Activity started by `SystemRestTimerActivityPresenter`.
///
/// The extension target compiles `Shared/` (for `RestTimerActivityAttributes`)
/// and `Spotter/Core/Design/Theme.swift` — nothing else from the app. No
/// SwiftData, no app-only helpers.
struct RestTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestTimerActivityAttributes.self) { context in
            LockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "timer")
                        .foregroundStyle(Theme.Colors.workout)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.isStale {
                        Text("Rest over")
                            .font(Theme.Typography.metricSmall)
                    } else {
                        Text(timerInterval: context.state.restInterval, countsDown: true)
                            .font(Theme.Typography.metricSmall)
                            .monospacedDigit()
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    if let exerciseName = context.state.exerciseName {
                        Text(exerciseName)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if !context.isStale {
                        ProgressView(timerInterval: context.state.restInterval, countsDown: true)
                            .tint(Theme.Colors.workout)
                    }
                }
            } compactLeading: {
                Image(systemName: "timer")
                    .foregroundStyle(Theme.Colors.workout)
            } compactTrailing: {
                if context.isStale {
                    Text("0:00")
                        .monospacedDigit()
                } else {
                    Text(timerInterval: context.state.restInterval, countsDown: true)
                        .monospacedDigit()
                        .frame(maxWidth: 44)
                }
            } minimal: {
                Image(systemName: "timer")
                    .foregroundStyle(Theme.Colors.workout)
            }
        }
    }
}

/// Lock Screen / notification-centre presentation.
private struct LockScreenView: View {
    let context: ActivityViewContext<RestTimerActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Label(context.attributes.workoutName, systemImage: "figure.strengthtraining.traditional")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
                Spacer()
                if let exerciseName = context.state.exerciseName {
                    Text(exerciseName)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                        .lineLimit(1)
                }
            }

            if context.isStale {
                Text("Rest over")
                    .font(Theme.Typography.metric)
                    .foregroundStyle(Theme.Colors.primaryText)
            } else {
                Text(timerInterval: context.state.restInterval, countsDown: true)
                    .font(Theme.Typography.metric)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.primaryText)

                ProgressView(timerInterval: context.state.restInterval, countsDown: true)
                    .tint(Theme.Colors.workout)
            }
        }
        .padding(Theme.Spacing.lg)
        .activityBackgroundTint(Theme.Colors.groupedBackground)
    }
}

// No `#Preview` here: the Live Activity preview macro's exact signature
// (`as:`/`using:`/`contentStates:`) isn't one this repo already uses
// elsewhere, and there is no compiler on this machine to verify it against.
// `LockScreenView` above takes a plain `ActivityViewContext`, so it can be
// previewed on a real device build without it.
