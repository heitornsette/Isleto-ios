import Foundation
import XCTest
@testable import IsletoCore

final class HabitStoreTests: XCTestCase {
    private let calendar = TestTime.calendar
    private let today = TestTime.date(2026, 11, 17)

    private func day(_ offset: Int) -> Date {
        today.addingTimeInterval(TimeInterval(offset * 86_400))
    }

    /// Same case as the desktop test `habits_can_be_added_checked_and_removed`.
    func testHabitsCanBeAddedCheckedAndRemoved() throws {
        let habits = HabitStore(database: try IsletoDatabase.inMemory())

        XCTAssertFalse(try habits.add(name: "   "), "empty name")
        XCTAssertTrue(try habits.add(name: "Meditar"))
        var list = try habits.list(on: today, calendar: calendar)
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].doneToday, false)
        XCTAssertEqual(list[0].streak, 0)

        try habits.toggle(id: list[0].id, on: today, calendar: calendar)
        list = try habits.list(on: today, calendar: calendar)
        XCTAssertEqual(list[0].doneToday, true)
        XCTAssertEqual(list[0].streak, 1)

        // Toggling again undoes today's check.
        try habits.toggle(id: list[0].id, on: today, calendar: calendar)
        XCTAssertFalse(try habits.list(on: today, calendar: calendar)[0].doneToday)

        // The limit and the name length.
        for name in ["A", "B", "C"] {
            XCTAssertTrue(try habits.add(name: name))
        }
        XCTAssertFalse(try habits.add(name: "E"), "over the limit")
        try habits.delete(id: list[0].id)
        XCTAssertTrue(try habits.add(name: String(repeating: "x", count: 60)))
        let last = try XCTUnwrap(try habits.list(on: today, calendar: calendar).last)
        XCTAssertEqual(last.name.count, HabitStore.maxNameLength)
    }

    func testStreakKeepsYesterdaysUntilTheDayEnds() throws {
        let habits = HabitStore(database: try IsletoDatabase.inMemory())
        try habits.add(name: "Ler")
        let id = try habits.list(calendar: calendar)[0].id
        for offset in [-3, -2, -1] {
            try habits.toggle(id: id, on: day(offset), calendar: calendar)
        }
        let habit = try habits.list(on: today, calendar: calendar)[0]
        XCTAssertFalse(habit.doneToday)
        XCTAssertEqual(habit.streak, 3)

        try habits.toggle(id: id, on: today, calendar: calendar)
        XCTAssertEqual(try habits.list(on: today, calendar: calendar)[0].streak, 4)
        // Two days later without checks: lost.
        XCTAssertEqual(try habits.list(on: day(2), calendar: calendar)[0].streak, 0)
    }

    func testDeletingAHabitRemovesItsChecks() throws {
        let db = try IsletoDatabase.inMemory()
        let habits = HabitStore(database: db)
        try habits.add(name: "Ler")
        let id = try habits.list(calendar: calendar)[0].id
        try habits.toggle(id: id, on: today, calendar: calendar)
        try habits.delete(id: id)
        XCTAssertEqual(try db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM habit_checks") }, 0)
    }
}
