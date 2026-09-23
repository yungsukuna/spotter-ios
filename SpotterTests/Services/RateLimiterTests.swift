import Foundation
import Testing

@testable import Spotter

/// ``RateLimiter`` is what stands between the app and Open Food Facts
/// blocking it for exceeding 15 requests/minute, so its boundary behaviour —
/// exactly `maxRequests` allowed, the next one rejected, and the window
/// actually expiring — is worth pinning down precisely.
///
/// A mutable box supplies "now" so the window can be advanced deterministically
/// instead of sleeping for real seconds in a test.
@Suite("RateLimiter")
struct RateLimiterTests {

    private final class MutableClock: @unchecked Sendable {
        var current = Date(timeIntervalSince1970: 1_000_000)
    }

    @Test("Exactly maxRequests calls succeed within the window")
    func allowsUpToTheLimit() async throws {
        let limiter = RateLimiter(maxRequests: 3, windowSeconds: 60)
        try await limiter.acquireOrThrow()
        try await limiter.acquireOrThrow()
        try await limiter.acquireOrThrow()
        #expect(await limiter.currentCount == 3)
    }

    @Test("The call one past the limit throws rateLimited")
    func rejectsOneOverTheLimit() async throws {
        let limiter = RateLimiter(maxRequests: 2, windowSeconds: 60)
        try await limiter.acquireOrThrow()
        try await limiter.acquireOrThrow()

        let error = try await #require(throws: FoodDataError.self) {
            try await limiter.acquireOrThrow()
        }
        #expect(error == .rateLimited)
    }

    @Test("A call is allowed again once the window has fully elapsed")
    func allowsAgainAfterWindowExpires() async throws {
        let clock = MutableClock()
        let limiter = RateLimiter(maxRequests: 1, windowSeconds: 60, now: { clock.current })

        try await limiter.acquireOrThrow()
        await #expect(throws: FoodDataError.self) {
            try await limiter.acquireOrThrow()
        }

        // Move time forward past the window.
        clock.current = clock.current.addingTimeInterval(61)

        // Should succeed now that the earlier timestamp has expired.
        try await limiter.acquireOrThrow()
        #expect(await limiter.currentCount == 1)
    }

    @Test("A timestamp exactly at the window boundary is treated as expired")
    func boundaryTimestampIsExpired() async throws {
        let clock = MutableClock()
        let limiter = RateLimiter(maxRequests: 1, windowSeconds: 60, now: { clock.current })

        try await limiter.acquireOrThrow()
        clock.current = clock.current.addingTimeInterval(60)

        // At exactly 60s the first call's timestamp is `>= windowSeconds` old
        // and is pruned, so this must succeed rather than throw.
        try await limiter.acquireOrThrow()
        #expect(await limiter.currentCount == 1)
    }
}
