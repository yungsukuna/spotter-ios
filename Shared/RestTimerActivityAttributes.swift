import ActivityKit
import Foundation

/// Shared between the app (which starts/updates/ends the Live Activity) and
/// the `SpotterWidgets` extension (which renders it). Kept in `Shared/` — the
/// only folder compiled into both targets — so the two sides can never drift
/// on the shape of the content state.
///
/// `Shared/` may only depend on Foundation-level, first-party frameworks: no
/// app types, no SwiftData models. `workoutName` is fixed for the lifetime of
/// one Live Activity (a rest timer never moves between workouts), so it is
/// part of the attributes rather than the content state. `exerciseName` can
/// change set to set, so it lives in `ContentState`.
struct RestTimerActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// When the rest period ends. Drives the countdown text and progress
        /// view directly via `Text(timerInterval:countsDown:)` /
        /// `ProgressView(timerInterval:countsDown:)` — no manual ticking.
        var endDate: Date
        /// The exercise the completed set belonged to, when known.
        var exerciseName: String?
    }

    /// The workout this rest timer belongs to. Fixed for the activity's
    /// lifetime.
    var workoutName: String
}
