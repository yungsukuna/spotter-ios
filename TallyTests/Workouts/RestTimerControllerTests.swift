import Foundation
import Testing

@testable import Tally

@Suite("RestTimerController")
struct RestTimerControllerTests {

    @Test("Starting a timer schedules a notification when asked to")
    func startingSchedulesNotification() {
        let notifier = MockRestTimerNotifier()
        let controller = RestTimerController(notifier: notifier)
        let now = Date(timeIntervalSince1970: 0)

        controller.start(duration: 90, notify: true, now: now)

        #expect(controller.isActive)
        #expect(controller.secondsRemaining(now: now) == 90)
        #expect(notifier.scheduledIdentifiers.count == 1)
    }

    @Test("Starting without notifications skips scheduling")
    func startingWithoutNotificationsSkipsScheduling() {
        let notifier = MockRestTimerNotifier()
        let controller = RestTimerController(notifier: notifier)

        controller.start(duration: 60, notify: false)

        #expect(notifier.scheduledIdentifiers.isEmpty)
    }

    @Test("Seconds remaining counts down and clamps at zero")
    func secondsRemainingCountsDown() {
        let controller = RestTimerController(notifier: MockRestTimerNotifier())
        let now = Date(timeIntervalSince1970: 0)
        controller.start(duration: 30, notify: false, now: now)

        #expect(controller.secondsRemaining(now: now.addingTimeInterval(10)) == 20)
        #expect(controller.secondsRemaining(now: now.addingTimeInterval(45)) == 0)
    }

    @Test("Adding time extends the countdown without rescheduling")
    func addingTimeExtends() {
        let notifier = MockRestTimerNotifier()
        let controller = RestTimerController(notifier: notifier)
        let now = Date(timeIntervalSince1970: 0)
        controller.start(duration: 30, notify: true, now: now)

        controller.addTime(15, now: now)

        #expect(controller.secondsRemaining(now: now) == 45)
        // The original notification is cancelled rather than left to fire at
        // the wrong time; no replacement is scheduled.
        #expect(notifier.cancelledIdentifiers.count == 1)
        #expect(notifier.scheduledIdentifiers.count == 1)
    }

    @Test("Subtracting past zero finishes the timer instead of going negative")
    func subtractingPastZeroFinishes() {
        let controller = RestTimerController(notifier: MockRestTimerNotifier())
        let now = Date(timeIntervalSince1970: 0)
        controller.start(duration: 10, notify: false, now: now)

        controller.addTime(-15, now: now)

        #expect(controller.state == .finished)
        #expect(controller.secondsRemaining(now: now) == 0)
    }

    @Test("Skipping cancels the pending notification and returns to idle")
    func skippingCancels() {
        let notifier = MockRestTimerNotifier()
        let controller = RestTimerController(notifier: notifier)
        controller.start(duration: 90, notify: true)

        controller.skip()

        #expect(controller.state == .idle)
        #expect(!controller.isActive)
        #expect(notifier.cancelledIdentifiers.count == 1)
    }

    @Test("Expiration only fires once the end date has passed")
    func expirationFiresAfterEndDate() {
        let controller = RestTimerController(notifier: MockRestTimerNotifier())
        let now = Date(timeIntervalSince1970: 0)
        controller.start(duration: 20, notify: false, now: now)

        controller.checkExpiration(now: now.addingTimeInterval(10))
        #expect(controller.isActive)

        controller.checkExpiration(now: now.addingTimeInterval(20))
        #expect(controller.state == .finished)
    }

    @Test("A fresh controller starts idle")
    func startsIdle() {
        let controller = RestTimerController(notifier: MockRestTimerNotifier())
        #expect(controller.state == .idle)
        #expect(!controller.isActive)
        #expect(controller.secondsRemaining() == 0)
    }
}
