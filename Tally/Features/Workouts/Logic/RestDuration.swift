import Foundation

/// Resolves how long the rest timer should run after a set is completed, or
/// whether it should run at all.
///
/// Kept as a pure function, separate from `ActiveWorkoutView.handleSetCompleted`,
/// so the override/default/off precedence can be unit tested without a view or
/// a `RestTimerController`.
enum RestDuration {

    /// - Parameters:
    ///   - exerciseOverride: `Exercise.restTimerSeconds`. Nil means "use
    ///     `globalDefault`"; zero means "no rest timer for this exercise",
    ///     which wins over the global default.
    ///   - globalDefault: `UserSettings.restTimerSeconds`.
    ///   - autoStart: `UserSettings.autoStartRestTimer`. False suppresses the
    ///     timer regardless of either duration.
    /// - Returns: seconds to rest, or nil when no timer should start.
    static func resolve(exerciseOverride: Int?, globalDefault: Int, autoStart: Bool) -> TimeInterval? {
        guard autoStart else { return nil }
        let seconds = exerciseOverride ?? globalDefault
        guard seconds > 0 else { return nil }
        return TimeInterval(seconds)
    }
}
