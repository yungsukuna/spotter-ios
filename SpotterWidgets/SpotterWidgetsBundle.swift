import SwiftUI
import WidgetKit

/// Entry point for the widget extension: the Home Screen / Lock Screen
/// "remaining today" widget and the rest-timer Live Activity.
@main
struct SpotterWidgetsBundle: WidgetBundle {
    var body: some Widget {
        DailyRemainingWidget()
        RestTimerLiveActivity()
    }
}
