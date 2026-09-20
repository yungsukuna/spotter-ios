import Combine
import SwiftUI

/// The visible, controllable rest timer pinned to the bottom of the logging
/// screen. Never requires leaving the screen to skip or adjust it.
struct RestTimerBar: View {
    var controller: RestTimerController

    @State private var now = Date()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
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
        .buttonStyle(.bordered)
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
        .background(.ultraThinMaterial)
        .onReceive(ticker) { date in
            now = date
            controller.checkExpiration(now: date)
        }
    }
}

#Preview {
    let controller = RestTimerController(notifier: MockRestTimerNotifier())
    controller.start(duration: 90, notify: false)
    return RestTimerBar(controller: controller)
}
