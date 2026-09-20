import Foundation

/// A client-side sliding-window rate limiter.
///
/// Open Food Facts allows 15 product reads per minute per IP (10/min for
/// search) and will block an app that ignores it — see the note on
/// ``OpenFoodFactsClient``. Enforcing the limit locally, before a request
/// ever goes out, keeps the app a good citizen even when a user mis-scans a
/// barcode several times in a row, and it turns a would-be HTTP 429 into a
/// same-process ``FoodDataError/rateLimited`` the UI can show immediately.
///
/// An actor so the timestamp list is never mutated from two calls at once —
/// scanning is inherently bursty (repeat frames of the same barcode), so
/// concurrent calls are the expected case, not an edge case.
actor RateLimiter {
    private let maxRequests: Int
    private let windowSeconds: TimeInterval
    private var timestamps: [Date] = []

    /// Injectable clock so tests can move time forward deterministically
    /// instead of sleeping for real seconds to observe the window expiring.
    private let now: @Sendable () -> Date

    init(maxRequests: Int, windowSeconds: TimeInterval, now: @escaping @Sendable () -> Date = Date.init) {
        self.maxRequests = maxRequests
        self.windowSeconds = windowSeconds
        self.now = now
    }

    /// Records this call and lets it through, or throws
    /// ``FoodDataError/rateLimited`` when the window already holds
    /// `maxRequests` calls.
    ///
    /// Expired timestamps are pruned first, so the window is always measured
    /// from "now" backwards rather than from whenever the limiter happened to
    /// be created.
    func acquireOrThrow() throws {
        let current = now()
        timestamps.removeAll { current.timeIntervalSince($0) >= windowSeconds }
        guard timestamps.count < maxRequests else {
            throw FoodDataError.rateLimited
        }
        timestamps.append(current)
    }

    /// Calls currently counted within the window. Exposed for tests; a real
    /// "requests remaining" UI could use it too.
    var currentCount: Int {
        timestamps.count
    }
}
