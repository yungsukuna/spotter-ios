import Foundation
import os
import UserNotifications

/// Schedules and cancels the local notification that lets the rest timer fire
/// even with the screen locked.
///
/// Abstracted behind a protocol — mirroring `FoodDataSource` elsewhere in the
/// app — so ``RestTimerController`` can be unit tested without touching
/// `UNUserNotificationCenter`, which is unavailable in a plain test process.
protocol RestTimerNotifying: Sendable {
    /// Schedule a one-shot notification `secondsFromNow` seconds out.
    /// Requests authorisation first if it has never been decided, so nothing
    /// has to ask for permission at launch.
    ///
    /// Synchronous on purpose: ``RestTimerController/start`` is itself
    /// synchronous (it is called from a set-complete tap) and tests need to
    /// observe the schedule without racing an unstructured `Task`. The system
    /// notifier hops internally for `UNUserNotificationCenter`.
    func scheduleNotification(secondsFromNow: TimeInterval, identifier: String)
    /// Cancel a previously scheduled notification. Safe to call when nothing
    /// is pending under that identifier.
    func cancelNotification(identifier: String)
}

/// Per-identifier generation counter shared between `scheduleNotification`
/// and `cancelNotification`.
///
/// `scheduleNotification`'s real work happens on an unstructured `Task`
/// after two `await`s (`notificationSettings()`, and on first run
/// `requestAuthorization`, which stays pending for as long as the permission
/// alert is on screen). If a skip, `addTime`, or a fresh `start` runs before
/// that `Task` reaches `center.add(request)`, the synchronous
/// `cancelNotification` it calls has nothing to remove yet, and the stale
/// request lands afterwards regardless. Bumping the generation on every
/// schedule and cancel — and having the `Task` check it still holds the
/// generation it started with, both before and after `add` — closes that
/// race without the protocol itself needing to become `async`.
///
/// A plain `final class` guarded by `OSAllocatedUnfairLock`, rather than an
/// actor, because `scheduleNotification`/`cancelNotification` are
/// synchronous, non-`async` protocol requirements.
private final class NotificationGenerationBox: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: [String: Int]())

    /// Advance `identifier` to a new generation and return it. Both
    /// scheduling and cancelling bump the counter, since either one
    /// invalidates whatever the previous generation was doing.
    @discardableResult
    func bump(_ identifier: String) -> Int {
        lock.withLock { generations in
            let next = (generations[identifier] ?? 0) + 1
            generations[identifier] = next
            return next
        }
    }

    /// The generation currently on record for `identifier`.
    func current(_ identifier: String) -> Int {
        lock.withLock { $0[identifier] ?? 0 }
    }
}

/// The real implementation, backed by `UserNotifications`.
///
/// Authorisation is requested lazily — the first time a timer actually
/// starts — rather than at launch, because asking before the user has done
/// anything is the kind of prompt people reflexively decline.
struct SystemRestTimerNotifier: RestTimerNotifying {
    /// Reference type held by the struct on purpose: `scheduleNotification`
    /// and `cancelNotification` are non-`mutating` protocol requirements, so
    /// the shared counter has to live behind a reference, not a stored
    /// value. See ``NotificationGenerationBox``.
    private let generations = NotificationGenerationBox()

    func scheduleNotification(secondsFromNow: TimeInterval, identifier: String) {
        // Captured synchronously, before the `Task` ever suspends, so a
        // race can only ever discard this attempt — it can never cause a
        // stale one to win.
        let generation = generations.bump(identifier)
        let fireDate = Date().addingTimeInterval(max(0, secondsFromNow))

        Task {
            await schedule(identifier: identifier, generation: generation, fireDate: fireDate)
        }
    }

    private func schedule(identifier: String, generation: Int, fireDate: Date) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }

        // A cancel or a newer schedule ran while we were awaiting
        // authorisation — this attempt is stale, bail before touching the
        // notification centre.
        guard generations.current(identifier) == generation else { return }

        let current = await center.notificationSettings()
        guard current.authorizationStatus == .authorized || current.authorizationStatus == .provisional else {
            return
        }

        // The trigger counts from *now*, not from when scheduling began, so
        // a slow permission prompt cannot make the timer fire late.
        let remainingSeconds = fireDate.timeIntervalSinceNow
        guard remainingSeconds > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Rest complete"
        content.body = "Time for your next set."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, remainingSeconds),
            repeats: false
        )
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try? await center.add(request)

        // A cancel could have raced in while `add` itself was awaiting —
        // check once more and remove what we just added if so.
        guard generations.current(identifier) == generation else {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            return
        }
    }

    func cancelNotification(identifier: String) {
        generations.bump(identifier)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}

/// Records calls instead of touching the notification centre. Used by
/// previews, and available to tests, so ``RestTimerController``'s state
/// machine can be exercised without the real notification stack.
final class MockRestTimerNotifier: RestTimerNotifying, @unchecked Sendable {
    private(set) var scheduledIdentifiers: [String] = []
    private(set) var cancelledIdentifiers: [String] = []

    func scheduleNotification(secondsFromNow: TimeInterval, identifier: String) {
        scheduledIdentifiers.append(identifier)
    }

    func cancelNotification(identifier: String) {
        cancelledIdentifiers.append(identifier)
    }
}
