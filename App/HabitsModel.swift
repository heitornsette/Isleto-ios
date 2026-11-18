import Foundation
import IsletoCore
import Observation
@preconcurrency import UserNotifications
import WidgetKit

/// State of the "Hábitos" tab. Rules live in IsletoCore (HabitStore, HabitRules);
/// this keeps what the screens show and schedules the reminders.
@MainActor
@Observable
final class HabitsModel {
    private(set) var habits: [Habit] = []
    private(set) var archived: [Habit] = []
    private(set) var categories: [HabitCategory] = []
    private(set) var errorText: String?
    /// Category filter of the list; nil shows all.
    var filter: Int64?

    var visibleHabits: [Habit] {
        guard let filter else { return habits }
        return habits.filter { $0.definition.categoryIDs.contains(filter) }
    }

    var today: Day { Day(.now) }

    func habit(id: Int64) -> Habit? {
        habits.first { $0.id == id } ?? archived.first { $0.id == id }
    }

    func reload() {
        do {
            let store = try SharedData.store().habits
            let all = try store.list(includeArchived: true)
            habits = all.filter { !$0.archived }
            archived = all.filter(\.archived)
            categories = try store.categories()
            if let filter, !categories.contains(where: { $0.id == filter }) {
                self.filter = nil
            }
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    /// Runs a change, then reloads the list, the widget and the reminders.
    @discardableResult
    private func change<T>(_ work: (HabitStore) throws -> T) -> T? {
        var result: T?
        do {
            result = try work(SharedData.store().habits)
        } catch {
            errorText = error.localizedDescription
        }
        reload()
        WidgetCenter.shared.reloadAllTimelines()
        CloudSync.shared.scheduleSync()
        Task { await syncReminders() }
        return result
    }

    // MARK: Days

    /// The card's button: check, relapse, +1 or the measure's target.
    func tap(_ habit: Habit) { change { try $0.tap(id: habit.id, day: today) } }
    func toggle(_ id: Int64, day: Day) { change { try $0.toggle(id: id, day: day) } }
    func setValue(_ id: Int64, day: Day, _ value: Double) { change { try $0.setValue(id: id, day: day, value) } }

    // MARK: Habits

    /// False if the name is empty.
    func create(_ definition: HabitDefinition) -> Bool {
        (change { try $0.create(definition) } ?? nil) != nil
    }

    func update(_ id: Int64, _ definition: HabitDefinition) -> Bool {
        change { try $0.update(id: id, definition) } ?? false
    }

    func setArchived(_ id: Int64, _ archived: Bool) { change { try $0.setArchived(id: id, archived) } }
    func delete(_ id: Int64) { change { try $0.delete(id: id) } }
    func reorder(_ ids: [Int64]) { change { try $0.reorder(ids) } }

    // MARK: Categories

    func createCategory(_ name: String) -> Int64? {
        change { try $0.createCategory(name: name) } ?? nil
    }

    func deleteCategory(_ id: Int64) { change { try $0.deleteCategory(id: id) } }

    // MARK: Reminders

    /// Replaces the pending habit reminders with the current plan.
    func syncReminders() async {
        let plan = HabitReminderPlanner.plan(habits)
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let old = pending.map(\.identifier).filter { $0.hasPrefix(HabitReminderPlanner.idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: old)
        guard !plan.isEmpty else { return }
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return }
        for reminder in plan {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            var components = DateComponents()
            components.hour = reminder.hour
            components.minute = reminder.minute
            components.weekday = reminder.appleWeekday
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            try? await center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
        }
    }
}
