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
    func begin(startDate: Date, endDate: Date, exerciseName: String?, workoutName: String)
    /// Update the running Live Activity's end date, e.g. after "+15s". A
    /// no-op if nothing is running.
    func update(endDate: Date)
    /// End the running Live Activity, if any.
    func end()
}

/// Does nothing. The default for `RestTimerController.init` so existing
/// tests and previews never touch ActivityKit.
struct NoopRestTimerActivityPresenter: RestTimerActivityPresenting {
    func begin(startDate: Date, endDate: Date, exerciseName: String?, workoutName: String) {}
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
    private(set) var lastStartDate: Date?
    private(set) var lastEndDate: Date?
    private(set) var lastExerciseName: String?
    private(set) var lastWorkoutName: String?

    func begin(startDate: Date, endDate: Date, exerciseName: String?, workoutName: String) {
        beginCount += 1
        lastStartDate = startDate
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

/// Generation counter plus the identity of the last-known activity, guarded
/// by a lock.
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
/// Only `Sendable` values are stored — the activity's `id` string, never the
/// `Activity` object itself, which is not `Sendable`. The live object is
/// looked up from `Activity.activities` inside each `Task` when needed.
///
/// A plain `final class` guarded by `OSAllocatedUnfairLock`, rather than an
/// actor, because the protocol requirements are synchronous, non-`async`.
private final class RestTimerActivityBox: @unchecked Sendable {
    private struct State: Sendable {
        var generation = 0
        var activityID: String?
        var exerciseName: String?
        var startDate: Date?
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())

    /// Advance to a new generation, returning it along with the id of
    /// whatever activity the previous generation had recorded (so the caller
    /// can end it). Called by both `begin` and `end`, since either
    /// invalidates whatever the previous generation was doing.
    @discardableResult
    func invalidate() -> (generation: Int, previousActivityID: String?) {
        lock.withLock { state in
            state.generation += 1
            let previous = state.activityID
            state.activityID = nil
            state.exerciseName = nil
            state.startDate = nil
            return (state.generation, previous)
        }
    }

    func currentGeneration() -> Int {
        lock.withLock { $0.generation }
    }

    /// Records the activity a still-current `begin` obtained. Returns false
    /// (and records nothing) if `generation` has since moved on.
    func setActivity(id: String, exerciseName: String?, startDate: Date, generation: Int) -> Bool {
        lock.withLock { state in
            guard state.generation == generation else { return false }
            state.activityID = id
            state.exerciseName = exerciseName
            state.startDate = startDate
            return true
        }
    }

    /// Generation, activity id, exercise name and start date read together
    /// under one lock acquisition, so a `skip`/`end` landing between separate
    /// reads can't pair a generation with an activity it no longer owns.
    func snapshot() -> (generation: Int, activityID: String?, exerciseName: String?, startDate: Date?) {
        lock.withLock { ($0.generation, $0.activityID, $0.exerciseName, $0.startDate) }
    }
}

/// The real implementation, backed by ActivityKit.
struct SystemRestTimerActivityPresenter: RestTimerActivityPresenting {
    private let box = RestTimerActivityBox()

    func begin(startDate: Date, endDate: Date, exerciseName: String?, workoutName: String) {
        let (generation, previousActivityID) = box.invalidate()
        let activitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled

        Task {
            // Always clear out whatever came before, even if the Settings
            // toggle turned Live Activities off mid-session.
            if let previousActivityID {
                await Self.endActivity(id: previousActivityID)
            }

            guard activitiesEnabled else { return }
            // A cancel or a newer `begin` ran while we were ending the
            // previous activity — this attempt is stale, bail before
            // requesting a new one.
            guard box.currentGeneration() == generation else { return }

            let attributes = RestTimerActivityAttributes(workoutName: workoutName)
            let state = RestTimerActivityAttributes.ContentState(
                startDate: startDate,
                endDate: endDate,
                exerciseName: exerciseName
            )
            let content = ActivityContent(state: state, staleDate: endDate)

            guard let activity = try? Activity<RestTimerActivityAttributes>.request(
                attributes: attributes,
                content: content,
                pushType: nil
            ) else {
                return
            }

            // A cancel could have raced in while `request` itself was
            // resolving — if so, end what we just started.
            if !box.setActivity(
                id: activity.id,
                exerciseName: exerciseName,
                startDate: startDate,
                generation: generation
            ) {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    func update(endDate: Date) {
        let (generation, maybeActivityID, exerciseName, maybeStartDate) = box.snapshot()
        guard let activityID = maybeActivityID, let startDate = maybeStartDate else { return }

        Task {
            guard box.currentGeneration() == generation else { return }
            guard let activity = Activity<RestTimerActivityAttributes>.activities.first(where: { $0.id == activityID }) else {
                return
            }
            let updatedState = RestTimerActivityAttributes.ContentState(
                startDate: startDate,
                endDate: endDate,
                exerciseName: exerciseName
            )
            await activity.update(ActivityContent(state: updatedState, staleDate: endDate))
        }
    }

    func end() {
        box.invalidate()

        Task {
            // Ends the activity this presenter started, and also sweeps
            // orphans: after the app is killed mid-rest and relaunched, this
            // presenter's box starts fresh with no record of the activity
            // still alive in ActivityKit. A `begin` that lands after this
            // `end` records its own id, which the sweep then leaves alone.
            for activity in Activity<RestTimerActivityAttributes>.activities {
                if box.snapshot().activityID == activity.id { continue }
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private static func endActivity(id: String) async {
        for activity in Activity<RestTimerActivityAttributes>.activities where activity.id == id {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
