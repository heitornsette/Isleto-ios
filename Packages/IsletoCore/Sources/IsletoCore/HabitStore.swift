import Foundation
import GRDB

/// Habits, in the desktop tables plus the v5 columns.
public struct HabitStore: Sendable {
    /// History loaded with each habit (same window as the desktop streak query).
    public static let historyDays = 400

    private let database: DatabaseQueue

    public init(database: DatabaseQueue) {
        self.database = database
    }

    // MARK: Reading

    /// Habits in the user's order, with history and streak.
    public func list(includeArchived: Bool = false, on date: Date = .now, calendar: Calendar = .current) throws -> [Habit] {
        try database.read { try Self.list($0, today: Day(date, calendar: calendar), includeArchived: includeArchived) }
    }

    public func habit(id: Int64, on date: Date = .now, calendar: Calendar = .current) throws -> Habit? {
        try list(includeArchived: true, on: date, calendar: calendar).first { $0.id == id }
    }

    static func list(_ db: Database, today: Day, includeArchived: Bool) throws -> [Habit] {
        let filter = includeArchived ? "" : "WHERE archived = 0"
        let rows = try Row.fetchAll(db, sql: """
            SELECT id, name, created_at, description, icon, color, kind, schedule, record,
                   target, unit, reminders, archived, sort_order
            FROM habits \(filter) ORDER BY sort_order, id
            """)
        guard !rows.isEmpty else { return [] }

        var values: [Int64: [Int: Double]] = [:]
        let since = today.adding(-historyDays).string
        for row in try Row.fetchAll(db, sql: "SELECT habit_id, day, value FROM habit_checks WHERE day >= ?", arguments: [since]) {
            let id: Int64 = row["habit_id"]
            let dayText: String = row["day"]
            if let day = Day(dayText) {
                values[id, default: [:]][day.number] = row["value"]
            }
        }
        var categories: [Int64: Set<Int64>] = [:]
        for row in try Row.fetchAll(db, sql: "SELECT habit_id, category_id FROM habit_category_links") {
            categories[row["habit_id"], default: []].insert(row["category_id"])
        }

        return rows.map { row in
            let id: Int64 = row["id"]
            let createdText: String = row["created_at"]
            let definition = HabitDefinition(
                name: row["name"],
                description: row["description"],
                icon: row["icon"],
                color: row["color"],
                kind: HabitKind(rawValue: row["kind"]) ?? .build,
                schedule: HabitSchedule(storage: row["schedule"]),
                record: HabitRecord(rawValue: row["record"]) ?? .check,
                target: row["target"],
                unit: row["unit"],
                reminders: ReminderTime.list(storage: row["reminders"]),
                categoryIDs: categories[id] ?? []
            )
            return Habit(
                id: id,
                definition: definition,
                archived: (row["archived"] as Int) != 0,
                sortOrder: row["sort_order"],
                created: Day(String(createdText.prefix(10))) ?? today,
                today: today,
                values: values[id] ?? [:]
            )
        }
    }

    // MARK: Editing habits

    /// Creates a habit at the end of the list. Nil if the name is empty.
    @discardableResult
    public func create(_ definition: HabitDefinition, at date: Date = .now, calendar: Calendar = .current) throws -> Int64? {
        guard let definition = definition.normalized() else { return nil }
        return try database.write { db in
            try db.execute(
                sql: """
                INSERT INTO habits (name, created_at, description, icon, color, kind, schedule, record,
                                    target, unit, reminders, sort_order)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, (SELECT COALESCE(MAX(sort_order), 0) + 1 FROM habits))
                """,
                arguments: [
                    definition.name, LocalTime.timestamp(date, calendar: calendar), definition.description,
                    definition.icon, definition.color, definition.kind.rawValue, definition.schedule.storage,
                    definition.record.rawValue, definition.target, definition.unit,
                    ReminderTime.storage(definition.reminders),
                ]
            )
            let id = db.lastInsertedRowID
            try Self.setCategories(definition.categoryIDs, habit: id, db)
            return id
        }
    }

    /// Shortcut used by tests and the screenshot demo.
    @discardableResult
    public func add(name: String) throws -> Bool {
        try create(HabitDefinition(name: name)) != nil
    }

    /// Saves the form. False if the name is empty.
    @discardableResult
    public func update(id: Int64, _ definition: HabitDefinition) throws -> Bool {
        guard let definition = definition.normalized() else { return false }
        try database.write { db in
            try db.execute(
                sql: """
                UPDATE habits SET name = ?, description = ?, icon = ?, color = ?, kind = ?, schedule = ?,
                                  record = ?, target = ?, unit = ?, reminders = ?
                WHERE id = ?
                """,
                arguments: [
                    definition.name, definition.description, definition.icon, definition.color,
                    definition.kind.rawValue, definition.schedule.storage, definition.record.rawValue,
                    definition.target, definition.unit, ReminderTime.storage(definition.reminders), id,
                ]
            )
            try Self.setCategories(definition.categoryIDs, habit: id, db)
        }
        return true
    }

    public func setArchived(id: Int64, _ archived: Bool) throws {
        try database.write { db in
            try db.execute(sql: "UPDATE habits SET archived = ? WHERE id = ?", arguments: [archived ? 1 : 0, id])
        }
    }

    public func delete(id: Int64) throws {
        try database.write { db in
            // Children first, like the desktop: it keeps foreign keys off.
            try db.execute(sql: "DELETE FROM habit_checks WHERE habit_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM habit_category_links WHERE habit_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM habits WHERE id = ?", arguments: [id])
        }
    }

    /// Saves the order of the list (first = 1).
    public func reorder(_ ids: [Int64]) throws {
        try database.write { db in
            for (index, id) in ids.enumerated() {
                try db.execute(sql: "UPDATE habits SET sort_order = ? WHERE id = ?", arguments: [index + 1, id])
            }
        }
    }

    // MARK: Recording days

    /// Check (or relapse) on the day; removes it if it was there. Same as the desktop toggle.
    public func toggle(id: Int64, on date: Date = .now, calendar: Calendar = .current) throws {
        try toggle(id: id, day: Day(date, calendar: calendar))
    }

    public func toggle(id: Int64, day: Day) throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM habit_checks WHERE habit_id = ? AND day = ?", arguments: [id, day.string])
            if db.changesCount == 0 {
                try db.execute(sql: "INSERT INTO habit_checks (habit_id, day, value) VALUES (?, ?, 1)", arguments: [id, day.string])
            }
        }
    }

    /// Adds to the day's count (negative to subtract). The day is removed at zero.
    public func increment(id: Int64, day: Day, by amount: Double = 1) throws {
        try database.writeWithoutTransaction { db in
            try db.inTransaction(.immediate) {
                let current = try Double.fetchOne(
                    db, sql: "SELECT value FROM habit_checks WHERE habit_id = ? AND day = ?", arguments: [id, day.string]
                ) ?? 0
                try Self.write(max(0, current + amount), id: id, day: day, db)
                return .commit
            }
        }
    }

    /// Sets the day's value; zero or less removes it.
    public func setValue(id: Int64, day: Day, _ value: Double) throws {
        try database.write { try Self.write(value, id: id, day: day, $0) }
    }

    /// What one tap on the card or the widget does: toggles a check or a relapse,
    /// adds one to a count, and toggles a measure between its target and nothing.
    public func tap(id: Int64, day: Day) throws {
        guard let habit = try database.read({ db in
            try Self.list(db, today: day, includeArchived: true).first { $0.id == id }
        }) else { return }
        switch habit.definition.record {
        case .check:
            try toggle(id: id, day: day)
        case .count:
            try increment(id: id, day: day)
        case .measure:
            try setValue(id: id, day: day, habit.value(on: day) > 0 ? 0 : habit.definition.target)
        }
    }

    private static func write(_ value: Double, id: Int64, day: Day, _ db: Database) throws {
        if value > 0 {
            try db.execute(
                sql: """
                INSERT INTO habit_checks (habit_id, day, value) VALUES (?, ?, ?)
                ON CONFLICT(habit_id, day) DO UPDATE SET value = excluded.value
                """,
                arguments: [id, day.string, value]
            )
        } else {
            try db.execute(sql: "DELETE FROM habit_checks WHERE habit_id = ? AND day = ?", arguments: [id, day.string])
        }
    }

    // MARK: Categories

    public func categories() throws -> [HabitCategory] {
        try database.read { db in
            try Row.fetchAll(db, sql: "SELECT id, name FROM habit_categories ORDER BY name COLLATE NOCASE").map {
                HabitCategory(id: $0["id"], name: $0["name"])
            }
        }
    }

    /// Creates a category, or returns the one with the same name. Nil if the name is empty.
    @discardableResult
    public func createCategory(name: String) throws -> Int64? {
        let name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(HabitDefinition.maxNameLength))
        guard !name.isEmpty else { return nil }
        return try database.write { db in
            if let existing = try Int64.fetchOne(db, sql: "SELECT id FROM habit_categories WHERE name = ?", arguments: [name]) {
                return existing
            }
            try db.execute(sql: "INSERT INTO habit_categories (name) VALUES (?)", arguments: [name])
            return db.lastInsertedRowID
        }
    }

    public func deleteCategory(id: Int64) throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM habit_category_links WHERE category_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM habit_categories WHERE id = ?", arguments: [id])
        }
    }

    private static func setCategories(_ ids: Set<Int64>, habit: Int64, _ db: Database) throws {
        try db.execute(sql: "DELETE FROM habit_category_links WHERE habit_id = ?", arguments: [habit])
        for category in ids.sorted() {
            try db.execute(
                sql: "INSERT OR IGNORE INTO habit_category_links (habit_id, category_id) SELECT ?, id FROM habit_categories WHERE id = ?",
                arguments: [habit, category]
            )
        }
    }
}
