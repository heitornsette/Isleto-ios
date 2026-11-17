import Foundation
import GRDB

public struct Habit: Equatable, Sendable, Identifiable {
    public let id: Int64
    public let name: String
    public let doneToday: Bool
    public let streak: Int

    public init(id: Int64, name: String, doneToday: Bool, streak: Int) {
        self.id = id
        self.name = name
        self.doneToday = doneToday
        self.streak = streak
    }
}

/// Daily habits, ported from the desktop (`isleto/src/db.rs`), same limits and rules.
public struct HabitStore: Sendable {
    /// The desktop panel has room for this many habits.
    public static let maxHabits = 4
    /// Longest habit name, in characters.
    public static let maxNameLength = 24

    private let database: DatabaseQueue

    public init(database: DatabaseQueue) {
        self.database = database
    }

    /// Habits with today's check and the current streak.
    public func list(on date: Date = .now, calendar: Calendar = .current) throws -> [Habit] {
        try database.read { try Self.list($0, day: LocalTime.day(date, calendar: calendar)) }
    }

    /// Adds a habit. False if the name is empty or the limit was reached.
    @discardableResult
    public func add(name: String) throws -> Bool {
        let name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxNameLength))
        guard !name.isEmpty else { return false }
        return try database.writeWithoutTransaction { db in
            var added = false
            try db.inTransaction(.immediate) {
                let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM habits") ?? 0
                if count < Self.maxHabits {
                    try db.execute(sql: "INSERT INTO habits (name) VALUES (?)", arguments: [name])
                    added = true
                }
                return .commit
            }
            return added
        }
    }

    public func delete(id: Int64) throws {
        try database.write { db in
            // Checks go first, like the desktop: it keeps foreign keys off.
            try db.execute(sql: "DELETE FROM habit_checks WHERE habit_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM habits WHERE id = ?", arguments: [id])
        }
    }

    /// Checks the habit for the day, or removes the check if it was already there.
    public func toggle(id: Int64, on date: Date = .now, calendar: Calendar = .current) throws {
        let day = LocalTime.day(date, calendar: calendar)
        try database.write { db in
            try db.execute(sql: "DELETE FROM habit_checks WHERE habit_id = ? AND day = ?", arguments: [id, day])
            if db.changesCount == 0 {
                try db.execute(sql: "INSERT INTO habit_checks (habit_id, day) VALUES (?, ?)", arguments: [id, day])
            }
        }
    }

    static func list(_ db: Database, day: String) throws -> [Habit] {
        let today = HabitStreak.dayNumber(day) ?? 0
        return try Row.fetchAll(db, sql: "SELECT id, name FROM habits ORDER BY id").map { row in
            let id: Int64 = row["id"]
            let name: String = row["name"]
            let days = try String.fetchAll(
                db,
                sql: "SELECT day FROM habit_checks WHERE habit_id = ? ORDER BY day DESC LIMIT 400",
                arguments: [id]
            ).compactMap(HabitStreak.dayNumber)
            return Habit(
                id: id,
                name: name,
                doneToday: days.first == today,
                streak: HabitStreak.streak(daysNewestFirst: days, today: today)
            )
        }
    }
}
