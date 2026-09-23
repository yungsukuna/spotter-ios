import ActivityKit
import Foundation
import Testing

@testable import Tally

/// Covers the two things the plan calls out as CI-verifiable for the Live
/// Activity: `RestTimerController` calling through to its presenter at the
/// right points, and `ContentState`'s Codable round-trip. Everything else
/// (the actual `ActivityKit` request) needs a device — see
/// `SystemRestTimerActivityPresenter`.
@Suite("RestTimerController + RestTimerActivityPresenting")
struct RestTimerActivityPresentingTests {

    @Test("Starting a timer begins a Live Activity with the exercise and workout name")
    func startingBeginsActivity() {
        let presenter = MockRestTimerActivityPresenter()
        let controller = RestTimerController(notifier: MockRestTimerNotifier(), activityPresenter: presenter)
        let now = Date(timeIntervalSince1970: 0)

        controller.start(duration: 90, notify: false, exerciseName: "Bench Press", workoutName: "Push Day", now: now)

        #expect(presenter.beginCount == 1)
        #expect(presenter.lastExerciseName == "Bench Press")
        #expect(presenter.lastWorkoutName == "Push Day")
        #expect(presenter.lastEndDate == now.addingTimeInterval(90))
    }

    @Test("Adding time updates the Live Activity")
    func addingTimeUpdatesActivity() {
        let presenter = MockRestTimerActivityPresenter()
        let controller = RestTimerController(notifier: MockRestTimerNotifier(), activityPresenter: presenter)
        let now = Date(timeIntervalSince1970: 0)
        controller.start(duration: 30, notify: false, now: now)

        controller.addTime(15, now: now)

        #expect(presenter.updateCount == 1)
        #expect(presenter.lastEndDate == now.addingTimeInterval(45))
        #expect(presenter.endCount == 0)
    }

    @Test("Subtracting past zero ends the Live Activity instead of updating it")
    func subtractingPastZeroEndsActivity() {
        let presenter = MockRestTimerActivityPresenter()
        let controller = RestTimerController(notifier: MockRestTimerNotifier(), activityPresenter: presenter)
        let now = Date(timeIntervalSince1970: 0)
        controller.start(duration: 10, notify: false, now: now)

        controller.addTime(-15, now: now)

        #expect(presenter.endCount == 1)
        #expect(presenter.updateCount == 0)
    }

    @Test("Skipping ends the Live Activity")
    func skippingEndsActivity() {
        let presenter = MockRestTimerActivityPresenter()
        let controller = RestTimerController(notifier: MockRestTimerNotifier(), activityPresenter: presenter)
        controller.start(duration: 90, notify: false)

        controller.skip()

        #expect(presenter.endCount == 1)
    }

    @Test("Expiring the timer ends the Live Activity")
    func expiringEndsActivity() {
        let presenter = MockRestTimerActivityPresenter()
        let controller = RestTimerController(notifier: MockRestTimerNotifier(), activityPresenter: presenter)
        let now = Date(timeIntervalSince1970: 0)
        controller.start(duration: 20, notify: false, now: now)

        controller.checkExpiration(now: now.addingTimeInterval(20))

        #expect(presenter.endCount == 1)
    }

    @Test("A default controller never touches the activity presenter's mock")
    func defaultControllerDoesNotTouchActivityPresenter() {
        // Existing call sites and tests construct `RestTimerController` with
        // only a notifier (or nothing at all), relying on
        // `NoopRestTimerActivityPresenter` as the default. This just
        // confirms that default still exists and the controller still works
        // without an explicit presenter.
        let controller = RestTimerController(notifier: MockRestTimerNotifier())
        controller.start(duration: 30, notify: false)
        #expect(controller.isActive)
    }

    @Test("ContentState round-trips through Codable")
    func contentStateCodableRoundTrip() throws {
        let original = RestTimerActivityAttributes.ContentState(
            endDate: Date(timeIntervalSince1970: 1_700_000_000),
            exerciseName: "Squat"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RestTimerActivityAttributes.ContentState.self, from: data)

        #expect(decoded == original)
    }

    @Test("ContentState round-trips through Codable when the exercise name is nil")
    func contentStateCodableRoundTripNilExercise() throws {
        let original = RestTimerActivityAttributes.ContentState(
            endDate: Date(timeIntervalSince1970: 1_700_000_000),
            exerciseName: nil
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RestTimerActivityAttributes.ContentState.self, from: data)

        #expect(decoded == original)
    }
}
