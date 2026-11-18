import Foundation
import GRDB
import XCTest
@testable import IsletoCore

final class HabitStoreTests: XCTestCase {
    private let calendar = TestTime.calendar
    private let today = TestTime.date(2026, 11, 17)
    private var todayDay: Day { Day(today, calendar: calendar) }

    private func makeStore() throws -> (HabitStore, DatabaseQueue) {
        let db = try IsletoDatabase.inMemory()
        return (HabitStore(database: db), db)
    }

    private func create(_ store: HabitStore, _ definition: HabitDefinition, daysAgo: Int = 30) throws -> Int64 {
        try XCTUnwrap(store.create(definition, at: today.addingTimeInterval(TimeInterval(-daysAgo * 86_400)), calendar: calendar))
    }

    /// Based on the desktop test `habits_can_be_added_checked_and_removed`, without its limit of 4.
    func testHabitsCanBeAddedCheckedAndRemoved() throws {
        let (habits, _) = try makeStore()

        XCTAssertNil(try habits.create(HabitDefinition(name: "   ")), "empty name")
        let id = try create(habits, HabitDefinition(name: "Meditar"))
        var list = try habits.list(on: today, calendar: calendar)
        XCTAssertEqual(list.count, 1)
        XCTAssertFalse(list[0].isComplete(todayDay))
        XCTAssertEqual(list[0].streak, Streak(0))

        try habits.toggle(id: id, on: today, calendar: calendar)
        list = try habits.list(on: today, calendar: calendar)
        XCTAssertTrue(list[0].isComplete(todayDay))
        XCTAssertEqual(list[0].streak, Streak(1))

        try habits.toggle(id: id, on: today, calendar: calendar)
        XCTAssertFalse(try habits.list(on: today, calendar: calendar)[0].isComplete(todayDay))

        // No limit on iOS.
        for name in ["A", "B", "C", "D", "E"] {
            XCTAssertTrue(try habits.add(name: name))
        }
        XCTAssertEqual(try habits.list(on: today, calendar: calendar).count, 6)
        try habits.delete(id: id)
        XCTAssertEqual(try habits.list(on: today, calendar: calendar).map(\.name), ["A", "B", "C", "D", "E"])
    }

    func testSavesAndReadsEveryField() throws {
        let (habits, _) = try makeStore()
        let health = try XCTUnwrap(habits.createCategory(name: "Saúde"))
        let definition = HabitDefinition(
            name: "  Correr  ",
            description: "Antes do trabalho",
            icon: "figure.run",
            color: "#FF6B5E",
            kind: .build,
            schedule: .weekdays([1, 3, 5]),
            record: .measure,
            target: 5,
            unit: "km",
            reminders: [ReminderTime(hour: 7, minute: 30)],
            categoryIDs: [health]
        )
        let id = try create(habits, definition)
        let saved = try XCTUnwrap(habits.habit(id: id, on: today, calendar: calendar))
        var expected = definition
        expected.name = "Correr"
        XCTAssertEqual(saved.definition, expected)

        var edited = saved.definition
        edited.kind = .quit
        XCTAssertTrue(try habits.update(id: id, edited))
        let after = try XCTUnwrap(habits.habit(id: id, on: today, calendar: calendar))
        XCTAssertEqual(after.definition.record, .check, "a quit habit records the relapse as a check")
        XCTAssertEqual(after.definition.unit, "")
    }

    func testCountAddsUpAndReachesTheTarget() throws {
        let (habits, _) = try makeStore()
        let id = try create(habits, HabitDefinition(name: "Copos", record: .count, target: 3))
        for _ in 0..<2 {
            try habits.tap(id: id, day: todayDay)
        }
        var habit = try XCTUnwrap(habits.habit(id: id, on: today, calendar: calendar))
        XCTAssertEqual(habit.todayValue, 2)
        XCTAssertEqual(habit.progressToday, 2.0 / 3.0, accuracy: 0.0001)
        XCTAssertFalse(habit.doneToday)

        try habits.tap(id: id, day: todayDay)
        habit = try XCTUnwrap(habits.habit(id: id, on: today, calendar: calendar))
        XCTAssertTrue(habit.doneToday)

        try habits.increment(id: id, day: todayDay, by: -10)
        habit = try XCTUnwrap(habits.habit(id: id, on: today, calendar: calendar))
        XCTAssertEqual(habit.todayValue, 0, "never below zero; the day is removed")
    }

    func testMeasureTapTogglesTheTarget() throws {
        let (habits, _) = try makeStore()
        let id = try create(habits, HabitDefinition(name: "Correr", record: .measure, target: 5, unit: "km"))
        try habits.setValue(id: id, day: todayDay, 2.5)
        XCTAssertFalse(try XCTUnwrap(habits.habit(id: id, on: today, calendar: calendar)).doneToday)
        try habits.tap(id: id, day: todayDay)
        XCTAssertEqual(try XCTUnwrap(habits.habit(id: id, on: today, calendar: calendar)).todayValue, 0)
        try habits.tap(id: id, day: todayDay)
        XCTAssertTrue(try XCTUnwrap(habits.habit(id: id, on: today, calendar: calendar)).doneToday)
    }

    func testArchiveHidesAndReorderSaves() throws {
        let (habits, _) = try makeStore()
        let a = try create(habits, HabitDefinition(name: "A"))
        let b = try create(habits, HabitDefinition(name: "B"))
        let c = try create(habits, HabitDefinition(name: "C"))
        try habits.reorder([c, a, b])
        XCTAssertEqual(try habits.list(on: today, calendar: calendar).map(\.name), ["C", "A", "B"])

        try habits.setArchived(id: a, true)
        XCTAssertEqual(try habits.list(on: today, calendar: calendar).map(\.name), ["C", "B"])
        XCTAssertEqual(try habits.list(includeArchived: true, on: today, calendar: calendar).count, 3)
        // New habits go to the end.
        try create(habits, HabitDefinition(name: "D"))
        XCTAssertEqual(try habits.list(on: today, calendar: calendar).map(\.name), ["C", "B", "D"])
    }

    func testCategoriesAreCreatedLinkedAndDeleted() throws {
        let (habits, db) = try makeStore()
        let study = try XCTUnwrap(habits.createCategory(name: "Estudo"))
        XCTAssertEqual(try habits.createCategory(name: " Estudo "), study, "same name, same category")
        XCTAssertNil(try habits.createCategory(name: "  "))
        let health = try XCTUnwrap(habits.createCategory(name: "Saúde"))
        XCTAssertEqual(try habits.categories().map(\.name), ["Estudo", "Saúde"])

        let id = try create(habits, HabitDefinition(name: "Ler", categoryIDs: [study, health, 999]))
        XCTAssertEqual(try habits.habit(id: id, on: today, calendar: calendar)?.definition.categoryIDs, [study, health])

        try habits.deleteCategory(id: study)
        XCTAssertEqual(try habits.habit(id: id, on: today, calendar: calendar)?.definition.categoryIDs, [health])
        try habits.delete(id: id)
        XCTAssertEqual(try db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM habit_category_links") }, 0)
    }

    func testDeletingAHabitRemovesItsChecks() throws {
        let (habits, db) = try makeStore()
        let id = try create(habits, HabitDefinition(name: "Ler"))
        try habits.toggle(id: id, on: today, calendar: calendar)
        try habits.delete(id: id)
        XCTAssertEqual(try db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM habit_checks") }, 0)
    }

    /// A habit made by the desktop (or before v5) reads with the defaults.
    func testDesktopHabitsReadWithDefaults() throws {
        let (habits, db) = try makeStore()
        try db.write { db in
            try db.execute(sql: "INSERT INTO habits (name, created_at) VALUES ('Meditar', '2026-11-01 08:00:00')")
            try db.execute(sql: "INSERT INTO habit_checks (habit_id, day) VALUES (1, '2026-11-17')")
        }
        let habit = try XCTUnwrap(habits.list(on: today, calendar: calendar).first)
        XCTAssertEqual(habit.definition.kind, .build)
        XCTAssertEqual(habit.definition.schedule, .daily)
        XCTAssertEqual(habit.definition.record, .check)
        XCTAssertEqual(habit.created, Day("2026-11-01"))
        XCTAssertTrue(habit.doneToday)
    }
}
