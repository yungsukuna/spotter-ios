import Foundation
import SwiftUI

/// Runtime configuration read from the build settings.
///
/// The USDA key travels: `Secrets.xcconfig` → `Config/App.xcconfig` →
/// `Info.plist` (as `USDAAPIKey`) → here. It is deliberately absent from the
/// repository, so a fresh clone builds and runs with USDA search disabled
/// rather than failing.
enum AppConfiguration {

    /// USDA FoodData Central API key, or nil when none is configured.
    ///
    /// Note that an unconfigured build produces the empty string rather than a
    /// missing key, because the xcconfig declares the variable with no value —
    /// so emptiness, not absence, is the check that matters.
    static var usdaAPIKey: String? {
        guard
            let raw = Bundle.main.object(forInfoDictionaryKey: "USDAAPIKey") as? String
        else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // The example file ships this literal; treat it as unconfigured rather
        // than sending it to the API and getting a confusing 403.
        guard !trimmed.isEmpty, trimmed != "your_key_here" else { return nil }
        return trimmed
    }

    static var isUSDAConfigured: Bool { usdaAPIKey != nil }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Sent as the Open Food Facts `User-Agent`. That API requires apps to
    /// identify themselves, and anonymous traffic can be blocked.
    static func openFoodFactsUserAgent(contact: String) -> String {
        let trimmed = contact.trimmingCharacters(in: .whitespacesAndNewlines)
        let contactPart = trimmed.isEmpty ? "github.com/yungsukuna/tally-ios" : trimmed
        return "Spotter/\(appVersion) (\(contactPart))"
    }
}

/// Dependencies the views need that are not SwiftData models.
///
/// Injected through the environment so a preview or a test can substitute
/// ``MockFoodDataSource`` without any global mutable state.
@Observable
final class AppEnvironment {
    var foodDataSource: any FoodDataSource

    init(foodDataSource: any FoodDataSource) {
        self.foodDataSource = foodDataSource
    }

    /// Previews and tests: entirely offline, with a small sample catalogue.
    static func preview() -> AppEnvironment {
        AppEnvironment(foodDataSource: MockFoodDataSource())
    }
}

private struct AppEnvironmentKey: EnvironmentKey {
    // Falls back to the mock. A view that somehow renders without the real
    // environment installed then shows sample data instead of crashing.
    //
    // Computed rather than a stored `let`: a stored default would be global
    // mutable state that Swift 6 requires isolating to an actor, and an
    // actor-isolated `defaultValue` does not satisfy `EnvironmentKey`.
    static var defaultValue: AppEnvironment { AppEnvironment.preview() }
}

extension EnvironmentValues {
    var appEnvironment: AppEnvironment {
        get { self[AppEnvironmentKey.self] }
        set { self[AppEnvironmentKey.self] = newValue }
    }
}
