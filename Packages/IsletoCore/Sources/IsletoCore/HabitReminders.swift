import Foundation

/// A repeating local notification for a habit.
public struct HabitReminder: Equatable, Sendable {
    public let id: String
    public let title: String
    public let body: String
    /// 1 = Monday ... 7 = Sunday, or nil for every day.
    public let weekday: Int?
    public let hour: Int
    public let minute: Int

    /// Weekday in Apple's calendar numbering (1 = Sunday ... 7 = Saturday).
    public var appleWeekday: Int? {
        weekday.map { $0 % 7 + 1 }
    }
}

/// Turns the habits' reminder times into repeating local notifications.
public enum HabitReminderPlanner {
    /// iOS keeps at most 64 pending local notifications per app; leave room for the focus one.
    public static let maxReminders = 60
    public static let idPrefix = "habit-"

    /// Daily and "times per week" habits remind every day; weekday habits only on
    /// their days. Archived habits never remind.
    public static func plan(_ habits: [Habit]) -> [HabitReminder] {
        var result: [HabitReminder] = []
        for habit in habits where !habit.archived {
            let definition = habit.definition
            let body = definition.kind == .quit ? "Continue firme: \(definition.name)" : "Hora de: \(definition.name)"
            var weekdays: [Int?] = [nil]
            if case .weekdays(let days) = definition.schedule {
                weekdays = days.sorted().map { Optional($0) }
            }
            for time in definition.reminders {
                for weekday in weekdays {
                    result.append(HabitReminder(
                        id: "\(idPrefix)\(habit.id)-\(weekday ?? 0)-\(time.text)",
                        title: "Isleto",
                        body: body,
                        weekday: weekday,
                        hour: time.hour,
                        minute: time.minute
                    ))
                }
            }
        }
        return Array(result.prefix(maxReminders))
    }
}
