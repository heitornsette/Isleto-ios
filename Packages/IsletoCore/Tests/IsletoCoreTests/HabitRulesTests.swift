import Foundation
import XCTest
@testable import IsletoCore

final class HabitRulesTests: XCTestCase {
    /// Tuesday 2026-11-17.
    private let today = Day("2026-11-17")!

    private func habit(_ definition: HabitDefinition, done offsets: [Int], value: Double = 1, createdDaysAgo: Int = 60) -> Habit {
        let values = Dictionary(uniqueKeysWithValues: offsets.map { (today.adding($0).number, value) })
        return Habit(id: 1, definition: definition, created: today.adding(-createdDaysAgo), today: today, values: values)
    }

    func testDayArithmeticAndWeekdays() {
        XCTAssertEqual(Day("1970-01-01")?.weekday, 4, "Thursday")
        XCTAssertEqual(today.weekday, 2, "Tuesday")
        XCTAssertEqual(today.startOfWeek.string, "2026-11-16")
        XCTAssertEqual(Day("2026-11-22")?.weekday, 7, "Sunday")
        XCTAssertEqual(Day("2026-11-22")?.startOfWeek.string, "2026-11-16")
        XCTAssertEqual(today.adding(15).string, "2026-12-02")
        XCTAssertEqual(Day("2024-02-28")?.adding(1).string, "2024-02-29")
        XCTAssertEqual(Day("1969-12-31")?.string, "1969-12-31")
        XCTAssertEqual(Day("1969-12-31")?.weekday, 3, "Wednesday")
    }

    func testDailyStreakKeepsTheDesktopRule() {
        let daily = HabitDefinition(name: "Ler")
        XCTAssertEqual(habit(daily, done: [0, -1, -2]).streak, Streak(3))
        XCTAssertEqual(habit(daily, done: [-1, -2]).streak, Streak(2), "yesterday's streak stands until the day ends")
        XCTAssertEqual(habit(daily, done: [-2, -3]).streak, Streak(0))
        XCTAssertEqual(habit(daily, done: [0, -1, -3]).streak, Streak(2))
    }

    func testWeekdaysStreakSkipsDaysNotDue() {
        // Monday, Wednesday, Friday. Today is Tuesday (not due).
        let mwf = HabitDefinition(name: "Correr", schedule: .weekdays([1, 3, 5]))
        // Done Monday (-1), Friday (-4), Wednesday (-6).
        XCTAssertEqual(habit(mwf, done: [-1, -4, -6]).streak, Streak(3))
        // Friday missed: only Monday counts.
        XCTAssertEqual(habit(mwf, done: [-1, -6]).streak, Streak(1))
        // A check on a day not due does not count.
        XCTAssertEqual(habit(mwf, done: [0, -1]).streak, Streak(1))

        // Due today and not done yet: the streak up to the last due day stands.
        let tuesdays = HabitDefinition(name: "Inglês", schedule: .weekdays([2]))
        XCTAssertEqual(habit(tuesdays, done: [-7, -14]).streak, Streak(2))
        XCTAssertEqual(habit(tuesdays, done: [0, -7, -14]).streak, Streak(3))
        XCTAssertEqual(habit(tuesdays, done: [-14]).streak, Streak(0))
    }

    func testTimesPerWeekStreakCountsWeeks() {
        let twice = HabitDefinition(name: "Academia", schedule: .timesPerWeek(2))
        // This week (Monday is -1): one check, not reached yet, does not break it.
        // Last week (-8...-2) and the week before (-15...-9): reached.
        XCTAssertEqual(habit(twice, done: [-1, -3, -5, -10, -12]).streak, Streak(2, .weeks))
        // Reached this week too.
        XCTAssertEqual(habit(twice, done: [0, -1, -3, -5, -10, -12]).streak, Streak(3, .weeks))
        // Last week missed.
        XCTAssertEqual(habit(twice, done: [0, -1, -3]).streak, Streak(1, .weeks))
        XCTAssertEqual(habit(twice, done: []).streak, Streak(0, .weeks))
    }

    func testQuitStreakCountsDaysSinceTheLastRelapse() {
        let quit = HabitDefinition(name: "Fumar", kind: .quit)
        XCTAssertEqual(habit(quit, done: [-5, -20]).streak, Streak(5))
        XCTAssertEqual(habit(quit, done: [0]).streak, Streak(0))
        XCTAssertEqual(habit(quit, done: [], createdDaysAgo: 9).streak, Streak(10), "clean since creation, today included")

        let relapsed = habit(quit, done: [-2])
        XCTAssertTrue(relapsed.isComplete(today.adding(-1)), "a clean day is a filled square")
        XCTAssertFalse(relapsed.isComplete(today.adding(-2)), "the relapse day is empty")
        XCTAssertFalse(relapsed.isComplete(today.adding(1)), "the future is empty")
        XCTAssertFalse(relapsed.isComplete(today.adding(-61)), "before creation is empty")
        XCTAssertTrue(relapsed.doneToday)
    }

    func testCountNeedsTheTargetForTheStreak() {
        let glasses = HabitDefinition(name: "Copos", record: .count, target: 8)
        XCTAssertEqual(habit(glasses, done: [0, -1], value: 8).streak, Streak(2))
        XCTAssertEqual(habit(glasses, done: [0, -1], value: 7).streak, Streak(0))
        XCTAssertEqual(habit(glasses, done: [-1], value: 7).completedDays(inWeekOf: today), 0)
    }

    func testScheduleStorageRoundTrips() {
        for schedule in [HabitSchedule.daily, .weekdays([1, 3, 5]), .timesPerWeek(3)] {
            XCTAssertEqual(HabitSchedule(storage: schedule.storage), schedule)
        }
        XCTAssertEqual(HabitSchedule.weekdays([5, 1, 3]).storage, "weekdays:1,3,5")
        XCTAssertEqual(HabitSchedule(storage: "weekdays:"), .daily)
        XCTAssertEqual(HabitSchedule(storage: "weekdays:0,9"), .daily)
        XCTAssertEqual(HabitSchedule(storage: "weekly:12"), .timesPerWeek(7))
        XCTAssertEqual(HabitSchedule(storage: "nonsense"), .daily)
    }

    func testRemindersStorageAndNormalization() {
        let times = ReminderTime.list(storage: "07:30,21:05,bad,25:99")
        XCTAssertEqual(times, [ReminderTime(hour: 7, minute: 30), ReminderTime(hour: 21, minute: 5), ReminderTime(hour: 23, minute: 59)])
        XCTAssertEqual(ReminderTime.storage(times), "07:30,21:05,23:59")

        let definition = HabitDefinition(
            name: "Ler",
            record: .count,
            target: 2.4,
            reminders: [ReminderTime(hour: 9, minute: 0), ReminderTime(hour: 8, minute: 0), ReminderTime(hour: 9, minute: 0),
                        ReminderTime(hour: 7, minute: 0), ReminderTime(hour: 6, minute: 0)]
        ).normalized()
        XCTAssertEqual(definition?.target, 2)
        XCTAssertEqual(definition?.reminders.map(\.text), ["06:00", "07:00", "08:00"])
        XCTAssertEqual(HabitDefinition(name: String(repeating: "x", count: 40)).normalized()?.name.count, 24)
    }

    func testReminderPlan() {
        let daily = Habit(
            id: 7,
            definition: HabitDefinition(name: "Ler", reminders: [ReminderTime(hour: 8, minute: 0), ReminderTime(hour: 20, minute: 30)]),
            created: today, today: today, values: [:]
        )
        let weekdays = Habit(
            id: 8,
            definition: HabitDefinition(name: "Fumar", kind: .quit, schedule: .weekdays([1, 7]), reminders: [ReminderTime(hour: 9, minute: 0)]),
            created: today, today: today, values: [:]
        )
        let archived = Habit(
            id: 9,
            definition: HabitDefinition(name: "Antigo", reminders: [ReminderTime(hour: 9, minute: 0)]),
            archived: true, created: today, today: today, values: [:]
        )
        let plan = HabitReminderPlanner.plan([daily, weekdays, archived])
        XCTAssertEqual(plan.map(\.id), ["habit-7-0-08:00", "habit-7-0-20:30", "habit-8-1-09:00", "habit-8-7-09:00"])
        XCTAssertEqual(plan[0].weekday, nil)
        XCTAssertEqual(plan[2].appleWeekday, 2, "Monday")
        XCTAssertEqual(plan[3].appleWeekday, 1, "Sunday")
        XCTAssertEqual(plan[2].body, "Continue firme: Fumar")
    }
}
