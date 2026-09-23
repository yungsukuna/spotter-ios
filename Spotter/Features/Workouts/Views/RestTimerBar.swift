import Combine
import SwiftUI

/// The visible, controllable rest timer pinned to the bottom of the logging
/// screen. Never requires leaving the screen to skip or adjust it.
///
/// The app suppresses `RestTimerNotifying`'s local notification while it is
/// in the foreground (there is no notification-centre delegate to force it
/// through), so this bar is the only signal a foregrounded lifter gets that
/// rest is over. It stays on screen in a "finished" style — with a haptic —
/// instead of just disappearing, and clears itself after a few seconds if
/// nobody taps it.
struct RestTimerBar: View {
    var controller: RestTimerController

    @State private var now = Date()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// How long the "Rest complete" banner stays up before clearing itself.
    private static let autoDismissDelay: TimeInterval = 3

    private var isFinished: Bool { controller.state == .finished }

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            if isFinished {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.Colors.success)

                Text("Rest complete")
                    .font(Theme.Typography.metricSmall)

                Spacer()

                Button("Dismiss") { controller.reset() }
                    .frame(minHeight: Theme.Layout.minimumTapTarget)
            } else {
                Image(systemName: "timer")
                    .foregroundStyle(Theme.Colors.workout)

                Text(Format.duration(TimeInterval(controller.secondsRemaining(now: now))))
                    .font(Theme.Typography.metricSmall)
                    .monospacedDigit()
                    .frame(minWidth: 64, alignment: .leading)

                Spacer()

                Button("-15s") { controller.addTime(-15, now: now) }
                    .frame(minHeight: Theme.Layout.minimumTapTarget)
                Button("+15s") { controller.addTime(15, now: now) }
                    .frame(minHeight: Theme.Layout.minimumTapTarget)
                Button("Skip") { controller.skip() }
                    .frame(minHeight: Theme.Layout.minimumTapTarget)
            }
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
        .background(.ultraThinMaterial)
        .onReceive(ticker) { date in
            now = date
            controller.checkExpiration(now: date)
        }
        .sensoryFeedback(.success, trigger: isFinished)
        // Clears the finished banner on its own in case the lifter has
        // already moved on and never taps "Dismiss". Keyed on `isFinished`,
        // so SwiftUI cancels the sleep if the state changes first, and the
        // closure stays on the main actor with the view.
        .task(id: isFinished) {
            guard isFinished else { return }
            try? await Task.sleep(for: .seconds(Self.autoDismissDelay))
            guard !Task.isCancelled, controller.state == .finished else { return }
            controller.reset()
        }
    }
}

#Preview("Running") {
    let controller = RestTimerController(notifier: MockRestTimerNotifier())
    controller.start(duration: 90, notify: false)
    return RestTimerBar(controller: controller)
}

#Preview("Finished") {
    let controller = RestTimerController(notifier: MockRestTimerNotifier())
    controller.start(duration: 1, notify: false, now: Date().addingTimeInterval(-5))
    controller.checkExpiration()
    return RestTimerBar(controller: controller)
}
