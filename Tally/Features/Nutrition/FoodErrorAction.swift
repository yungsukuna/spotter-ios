import Foundation

/// How the add-food screen should respond to a failed lookup.
///
/// Pulled out as its own type, separate from ``FoodDataError/isRetryable``,
/// because `isRetryable` alone can't distinguish `.missingAPIKey` from
/// `.productNotFound` — both are non-retryable, but one wants an explanation
/// and Settings link while the other wants a manual-entry button. Keeping the
/// mapping here means a new `FoodDataError` case is a compiler error at this
/// switch rather than a screen that silently shows the wrong control.
enum FoodErrorAction: Equatable {
    /// Offer a retry button.
    case retry
    /// Offer to type the food in by hand.
    case manualEntry
    /// Point at Settings; nothing to retry.
    case explainConfiguration
}

extension FoodDataError {
    var suggestedAction: FoodErrorAction {
        switch self {
        case .offline, .rateLimited, .serverError:
            .retry
        case .productNotFound, .decodingFailed:
            .manualEntry
        case .missingAPIKey:
            .explainConfiguration
        }
    }
}
