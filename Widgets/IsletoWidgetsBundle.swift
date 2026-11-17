import SwiftUI
import WidgetKit

/// One extension for every widget and Live Activity: each extension costs an App ID
/// on a free Apple ID.
@main
struct IsletoWidgetsBundle: WidgetBundle {
    var body: some Widget {
        CounterWidget()
        TimerLiveActivity()
    }
}
