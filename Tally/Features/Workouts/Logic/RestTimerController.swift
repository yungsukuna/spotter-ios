import Foundation

/// State machine for the rest timer shown at the bottom of the logging
/// screen.
///
/// Kept as a plain `@Observable` object rather than view state so it survives
/// the view's own re-renders while the countdown ticks, and so its behaviour
/// — starting, adjusting, skipping, expiring — can be unit tested against
/// fixed dates instead of real wall-clock time.
@Observable
final class RestTimerController {

    enum State: Equatable {
        case idle
        case running(endDate: Date)
        case finished
    }

    private(set) var state: State = .idle

    private let notifier: any RestTimerNotifying
    /// A single fixed identifier is enough: only one rest timer is ever
    /// running at a time, and starting a new one always supersedes it.
    private let notificationID = "com.tally.workouts.rest-timer"

    init(notifier: any RestTimerNotifying = SystemRestTimerNotifier()) {
        self.notifier = notifier
    }

    var isActive: Bool {
        if case .running = state { true } else { false }
    }

    /// Seconds left, rounded up so the display never flashes "0:00" a beat
    /// before the timer actually finishes. Zero once idle or finished.
    func secondsRemaining(now: Date = Date()) -> Int {
        guard case .running(let endDate) = state else { return 0 }
        return max(0, Int(endDate.timeIntervalSince(now).rounded(.up)))
    }

    /// Begin a rest period. Replaces whatever timer, if any, was already
    /// running, cancelling its pending notification first so two never fire.
    func start(duration: TimeInterval, notify: Bool, now: Date = Date()) {
        let endDate = now.addingTimeInterval(max(0, duration))
        state = .running(endDate: endDate)
        notifier.cancelNotification(identifier: notificationID)

        guard notify else { return }
        notifier.scheduleNotification(secondsFromNow: duration, identifier: notificationID)
    }

    /// Nudge the remaining time by `delta` seconds — positive for "+15s",
    /// negative for "-15s". A delta that would take the timer past zero
    /// finishes it instead of going negative.
    ///
    /// Deliberately does not reschedule the pending notification: once the
    /// user has touched the timer, the visible countdown becomes the source
    /// of truth, and a locked-screen notification firing at the *original*
    /// time would be confusing rather than merely imprecise. It is cancelled
    /// instead.
    func addTime(_ delta: TimeInterval, now: Date = Date()) {
        guard case .running(let endDate) = state else { return }
        let newEnd = endDate.addingTimeInterval(delta)
        notifier.cancelNotification(identifier: notificationID)
        if newEnd <= now {
            state = .finished
        } else {
            state = .running(endDate: newEnd)
        }
    }

    /// User-initiated stop. Cancels any pending notification so it does not
    /// fire after the user has already moved on.
    func skip() {
        state = .idle
        notifier.cancelNotification(identifier: notificationID)
    }

    /// Back to the starting state. Equivalent to ``skip()`` — kept as a
    /// separate name for callers that mean "reset for the next set" rather
    /// than "the user tapped skip".
    func reset() {
        skip()
    }

    /// Transition running → finished once the end date has passed. Intended
    /// to be called on a periodic tick (e.g. once a second) by whatever view
    /// is driving the visible countdown.
    func checkExpiration(now: Date = Date()) {
        guard case .running(let endDate) = state, endDate <= now else { return }
        state = .finished
        notifier.cancelNotification(identifier: notificationID)
    }
}
