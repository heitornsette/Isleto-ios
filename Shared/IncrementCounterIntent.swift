import AppIntents
import WidgetKit

/// "+1" button of the widget. Compiled into the app and the widget extension;
/// when tapped on the widget, it runs in the extension process.
struct IncrementCounterIntent: AppIntent {
    static let title: LocalizedStringResource = "Somar 1 ao contador"

    func perform() async throws -> some IntentResult {
        try SharedData.counter().increment()
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
