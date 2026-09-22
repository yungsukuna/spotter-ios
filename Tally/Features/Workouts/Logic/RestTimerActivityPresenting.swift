import ActivityKit
import Foundation
import os

/// Starts, updates and ends the rest-timer Live Activity. Abstracted behind a
/// protocol — mirroring `RestTimerNotifying` — so ``RestTimerController`` can
/// be unit tested without touching ActivityKit, which is unavailable in a
/// plain test process.
protocol RestTimerActivityPresenting: Sendable {
    /// Start a Live Activity for a rest period, replacing whatever one was
    /// already running.
    ///
    /// Synchronous on purpose: ``RestTimerController/start`` is itself
    /// synchronous (it is called from a set-complete tap) and tests need to
    /// observe the call without racing an unstructured `Task`. The system
    /// presenter hops internally for `Activity.request`.
    func begin(endDate: Date, exerciseName: String?, workoutName: String)
    /// Update the running Live Activity's end date, e.g. after "+15s". A
    /// no-op if nothing is running.
    func update(endDate: Date)
    /// End the running Live Activity, if any.
    func end()
}

/// Does nothing. The default for `RestTimerController.init` so existing
/// tests and previews never touch ActivityKit.
struct NoopRestTimerActivityPresenter: RestTimerActivityPresenting {
    func begin(endDate: Date, exerciseName: String?, workoutName: String) {}
    func update(endDate: Date) {}
    func end() {}
}

/// Records calls instead of touching ActivityKit. Available to tests so
/// ``RestTimerController``'s state machine can be exercised against the
/// presenter without the real Live Activity stack.
final class MockRestTimerActivityPresenter: RestTimerActivityPresenting, @unchecked Sendable {
    private(set) var beginCount = 0
    private(set) var updateCount = 0
    private(set) var endCount = 0
    private(set) var lastEndDate: Date?
    private(set) var lastExerciseName: String?
    private(set) var lastWorkoutName: String?

    func begin(endDate: Date, exerciseName: String?, workoutName: String) {
        beginCount += 1
        lastEndDate = endDate
        lastExerciseName = exerciseName
        lastWorkoutName = workoutName
    }

    func update(endDate: Date) {
        updateCount += 1
        lastEndDate = endDate
    }

    func end() {
        endCount += 1
    }
}

/// Generation counter plus the last-known activity, guarded by a lock.
///
/// Mirrors `NotificationGenerationBox` in `RestTimerNotifying.swift`.
/// `begin`'s real work — ending whatever activity came before, then
/// requesting a new one — happens on an unstructured `Task`. If `end` or a
/// fresh `begin` runs while that `Task` is still resolving, the request
/// landing afterwards would leave an orphaned activity behind: exactly the
/// "complete set, then skip" race the notifier's box exists to close. There
/// is only ever one rest-timer activity at a time, so a single counter (not
/// per-identifier) is enough.
///
/// A plain `final class` guarded by `OSAllocatedUnfairLock`, rather than an
/// actor, because the protocol requirements are synchronous, non-`async`.
private final class RestTimerActivityBox: @unchecked Sendable {
    private struct State {
        var generation = 0
        var activity: Activity<RestTimerActivityAttributes>?
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())

    /// Advance to a new generation, returning it along with whatever
    /// activity the previous generation had recorded (so the caller can end
    /// it). Called by both `begin` and `end`, since either invalidates
    /// whatever the previous generation was doing.
    @discardableResult
    func invalidate() -> (generation: Int, previousActivity: Activity<RestTimerActivityAttributes>?) {
        lock.withLock { state in
            state.generation += 1
            let previous = state.activity
            state.activity = nil
            return (state.generation, previous)
        }
    }

    func currentGeneration() -> Int {
        lock.withLock { $0.generation }
    }

    /// Records the activity a still-current `begin` obtained. No-op if
    /// `generation` has since moved on.
    func setActivity(_ activity: Activity<RestTimerActivityAttributes>, generation: Int) {
        lock.withLock { state in
            guard state.generation == generation else { return }
            state.activity = activity
        }
    }

    func currentActivity() -> Activity<RestTimerActivityAttributes>? {
        lock.withLock { $0.activity }
    }

    /// `generation` and `activity` read together under one lock acquisition,
    /// so a `skip`/`end` landing between two separate reads can't hand back
    /// a generation that no longer matches the activity it was paired with.
    func snapshot() -> (generation: Int, activity: Activity<RestTimerActivityAttributes>?) {
        lock.withLock { ($0.generation, $0.activity) }
    }
}

/// The real implementation, backed by ActivityKit.
struct SystemRestTimerActivityPresenter: RestTimerActivityPresenting {
    private let box = RestTimerActivityBox()

    func begin(endDate: Date, exerciseName: String?, workoutName: String) {
        let (generation, previousActivity) = box.invalidate()
        let activitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled

        let attributes = RestTimerActivityAttributes(workoutName: workoutName)
        let state = RestTimerActivityAttributes.ContentState(endDate: endDate, exerciseName: exerciseName)
        let content = ActivityContent(state: state, staleDate: endDate)

        Task {
            // Always clear out whatever came before, even if the Settings
            // toggle turned Live Activities off mid-session.
            if let previousActivity {
                await previousActivity.end(nil, dismissalPolicy: .immediate)
            }

            guard activitiesEnabled else { return }
            // A cancel or a newer `begin` ran while we were ending the
            // previous activity — this attempt is stale, bail before
            // requesting a new one.
            guard box.currentGeneration() == generation else { return }

            guard let activity = try? Activity<RestTimerActivityAttributes>.request(
                attributes: attributes,
                content: content,
                pushType: nil
            ) else {
                return
            }

            box.setActivity(activity, generation: generation)

            // A cancel could have raced in while `request` itself was
            // resolving — check once more and end what we just started.
            if box.currentGeneration() != generation {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    func update(endDate: Date) {
        let (generation, maybeActivity) = box.snapshot()
        guard let activity = maybeActivity else { return }

        Task {
            guard box.currentGeneration() == generation else { return }
            let updatedState = RestTimerActivityAttributes.ContentState(
                endDate: endDate,
                exerciseName: activity.content.state.exerciseName
            )
            let content = ActivityContent(state: updatedState, staleDate: endDate)
            await activity.update(content)
        }
    }

    func end() {
        let (_, previousActivity) = box.invalidate()

        Task {
            if let previousActivity {
                await previousActivity.end(nil, dismissalPolicy: .immediate)
            }
            // Orphan sweep: after the app is killed mid-rest and relaunched,
            // this presenter's box starts fresh with no reference to the
            // activity that's still alive in ActivityKit. Called both here
            // and once at launch (see `WorkoutsHomeView`), this cleans it up
            // regardless of which path finds it first.
            for activity in Activity<RestTimerActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
