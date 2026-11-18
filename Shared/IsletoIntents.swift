import AppIntents
import IsletoCore
import WidgetKit

// Widget buttons. Compiled into the app and the widget extension; when tapped on
// the widget, they run in the extension process and write to the App Group database.

struct AddWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Registrar um copo de água"

    func perform() async throws -> some IntentResult {
        try SharedData.store().water.add()
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

/// One tap on a habit: check, relapse, +1 or the measure's target (see HabitStore.tap).
struct ToggleHabitIntent: AppIntent {
    static let title: LocalizedStringResource = "Registrar hábito de hoje"

    @Parameter(title: "Hábito")
    var habitID: Int

    init() {}

    init(habitID: Int64) {
        self.habitID = Int(habitID)
    }

    func perform() async throws -> some IntentResult {
        try SharedData.store().habits.tap(id: Int64(habitID), day: Day(.now))
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
