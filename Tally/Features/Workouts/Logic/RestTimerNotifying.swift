import Foundation
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
    func scheduleNotification(secondsFromNow: TimeInterval, identifier: String) async
    /// Cancel a previously scheduled notification. Safe to call when nothing
    /// is pending under that identifier.
    func cancelNotification(identifier: String)
}

/// The real implementation, backed by `UserNotifications`.
///
/// Authorisation is requested lazily — the first time a timer actually
/// starts — rather than at launch, because asking before the user has done
/// anything is the kind of prompt people reflexively decline.
struct SystemRestTimerNotifier: RestTimerNotifying {
    func scheduleNotification(secondsFromNow: TimeInterval, identifier: String) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }

        let current = await center.notificationSettings()
        guard current.authorizationStatus == .authorized || current.authorizationStatus == .provisional else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Rest complete"
        content.body = "Time for your next set."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, secondsFromNow),
            repeats: false
        )
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try? await center.add(request)
    }

    func cancelNotification(identifier: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}

/// Records calls instead of touching the notification centre. Used by
/// previews, and available to tests, so ``RestTimerController``'s state
/// machine can be exercised without the real notification stack.
final class MockRestTimerNotifier: RestTimerNotifying, @unchecked Sendable {
    private(set) var scheduledIdentifiers: [String] = []
    private(set) var cancelledIdentifiers: [String] = []

    func scheduleNotification(secondsFromNow: TimeInterval, identifier: String) async {
        scheduledIdentifiers.append(identifier)
    }

    func cancelNotification(identifier: String) {
        cancelledIdentifiers.append(identifier)
    }
}
