import Foundation
import GRDB
import XCTest
@testable import IsletoCore

final class SchemaTests: XCTestCase {
    func testMigrateCreatesSchemaAndIsIdempotent() throws {
        let db = try IsletoDatabase.inMemory()
        try db.writeWithoutTransaction { try Schema.migrate($0) }

        let version = try db.read { try Schema.version($0) }
        XCTAssertEqual(version, Schema.migrations.count)
        try db.write { try $0.execute(sql: "INSERT INTO settings (key, value) VALUES ('a', 'b')") }
    }

    /// Guards the "same schema as the desktop" rule: a change here must be deliberate.
    func testTablesAndColumnsMatchTheDesktop() throws {
        let db = try IsletoDatabase.inMemory()
        let expected: [String: [String]] = [
            "settings": ["key", "value"],
            "focus_sessions": ["id", "finished_at", "minutes", "uuid", "updated_at", "updated_by", "dirty"],
            "water_logs": ["id", "logged_at", "ml", "uuid", "updated_at", "updated_by", "dirty"],
            "habits": [
                "id", "name", "created_at", "description", "icon", "color", "kind", "schedule",
                "record", "target", "unit", "reminders", "archived", "sort_order",
                "uuid", "updated_at", "updated_by", "dirty",
            ],
            "habit_checks": ["habit_id", "day", "value", "updated_at", "updated_by", "dirty"],
            "habit_categories": ["id", "name", "created_at", "uuid", "updated_at", "updated_by", "dirty"],
            "habit_category_links": ["habit_id", "category_id", "updated_at", "updated_by", "dirty"],
            "sync_state": ["id", "device_id", "cursor", "applying", "last_sync"],
            "sync_tombstones": ["tbl", "key", "row", "deleted_at", "deleted_by"],
        ]
        try db.read { db in
            let tables = try String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
            )
            XCTAssertEqual(tables, expected.keys.sorted())
            for (table, columns) in expected {
                let names = try Row.fetchAll(db, sql: "PRAGMA table_info(\(table))").map { $0["name"] as String }
                XCTAssertEqual(names, columns, table)
            }
        }
    }

    /// A database left at an older version (for example by an older desktop) is upgraded.
    func testUpgradesADatabaseFromAnOlderVersion() throws {
        let db = try DatabaseQueue()
        try db.write { db in
            try db.execute(sql: Schema.migrations[0])
            try db.execute(sql: Schema.migrations[1])
            try db.execute(sql: "PRAGMA user_version = 2")
            try db.execute(sql: "INSERT INTO focus_sessions (minutes) VALUES (25)")
        }
        try db.writeWithoutTransaction { try Schema.migrate($0) }

        try db.read { db in
            XCTAssertEqual(try Schema.version(db), Schema.migrations.count)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM focus_sessions"), 1)
        }
    }

    func testDefaultTimestampsUseTheDesktopFormat() throws {
        let db = try IsletoDatabase.inMemory()
        let loggedAt = try db.write { db -> String? in
            try db.execute(sql: "INSERT INTO water_logs (ml) VALUES (250)")
            return try String.fetchOne(db, sql: "SELECT logged_at FROM water_logs")
        }
        // "YYYY-MM-DD HH:MM:SS", local time, like the desktop.
        let pattern = #"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$"#
        XCTAssertNotNil(loggedAt?.range(of: pattern, options: .regularExpression))
    }
}
