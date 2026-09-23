import Testing

@testable import Spotter

@Suite("FoodDataError UI mapping")
struct FoodErrorActionTests {

    @Test("Product-not-found routes to manual entry")
    func notFoundRoutesToManualEntry() {
        #expect(FoodDataError.productNotFound.suggestedAction == .manualEntry)
    }

    @Test("Undecodable data also routes to manual entry")
    func decodingFailureRoutesToManualEntry() {
        #expect(FoodDataError.decodingFailed("bad json").suggestedAction == .manualEntry)
    }

    @Test("Offline, rate-limited, and server errors all offer a retry")
    func transientFailuresOfferRetry() {
        #expect(FoodDataError.offline.suggestedAction == .retry)
        #expect(FoodDataError.rateLimited.suggestedAction == .retry)
        #expect(FoodDataError.serverError(status: 500).suggestedAction == .retry)
    }

    @Test("A missing API key explains configuration instead of offering a retry")
    func missingKeyExplainsConfiguration() {
        #expect(FoodDataError.missingAPIKey.suggestedAction == .explainConfiguration)
    }

    @Test("Every retryable error is mapped to retry, and no others are")
    func retryableMatchesIsRetryable() {
        let allCases: [FoodDataError] = [
            .productNotFound, .offline, .decodingFailed("x"), .rateLimited,
            .missingAPIKey, .serverError(status: 503),
        ]
        for error in allCases {
            #expect((error.suggestedAction == .retry) == error.isRetryable)
        }
    }
}
