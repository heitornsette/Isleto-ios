import Foundation
import GRDB

/// Water drunk, in the desktop's `water_logs` table, with the desktop's rules:
/// totals and undo only consider today (local time).
public struct WaterStore: Sendable {
    /// Same defaults as the desktop config (`water_goal_ml`, `water_step_ml`).
    public static let goalMl = 2000
    public static let glassMl = 250

    private let database: DatabaseQueue

    public init(database: DatabaseQueue) {
        self.database = database
    }

    public func add(ml: Int = WaterStore.glassMl, at date: Date = .now, calendar: Calendar = .current) throws {
        try database.write { db in
            try db.execute(
                sql: "INSERT INTO water_logs (logged_at, ml) VALUES (?, ?)",
                arguments: [LocalTime.timestamp(date, calendar: calendar), ml]
            )
        }
    }

    /// Removes the last entry of the day. False if there was none.
    @discardableResult
    public func undoLast(on date: Date = .now, calendar: Calendar = .current) throws -> Bool {
        try database.write { db in
            try db.execute(
                sql: """
                DELETE FROM water_logs WHERE id = (
                    SELECT id FROM water_logs
                    WHERE date(logged_at) = ?
                    ORDER BY id DESC LIMIT 1
                )
                """,
                arguments: [LocalTime.day(date, calendar: calendar)]
            )
            return db.changesCount > 0
        }
    }

    /// Milliliters drunk on the day of `date`.
    public func total(on date: Date = .now, calendar: Calendar = .current) throws -> Int {
        try database.read { db in
            try Self.total(db, day: LocalTime.day(date, calendar: calendar))
        }
    }

    static func total(_ db: Database, day: String) throws -> Int {
        try Int.fetchOne(
            db,
            sql: "SELECT COALESCE(SUM(ml), 0) FROM water_logs WHERE date(logged_at) = ?",
            arguments: [day]
        ) ?? 0
    }
}
