import Foundation
import GRDB
import XCTest
@testable import IsletoCore

/// Migration v6: the triggers keep the sync columns and tombstones up to date while
/// the stores keep plain INSERT, UPDATE and DELETE. Same cases as the desktop test
/// `sync_columns_follow_inserts_updates_and_deletes`.
final class SyncSchemaTests: XCTestCase {
    private let calendar = TestTime.calendar
    private let today = TestTime.date(2026, 11, 17)

    private func count(_ db: DatabaseQueue, _ sql: String) throws -> Int {
        try db.read { try Int.fetchOne($0, sql: sql) ?? -1 }
    }

    func testNewRowsGetAUUIDAndWaitToBeSent() throws {
        let db = try IsletoDatabase.inMemory()
        let store = IsletoStore(database: db)
        try store.habits.create(HabitDefinition(name: "Ler"), at: today, calendar: calendar)
        try store.water.add(at: today, calendar: calendar)
        try store.focus.start(now: today, calendar: calendar)
        try store.focus.settle(now: today.addingTimeInterval(3600), calendar: calendar)

        let pattern = #"^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"#
        try db.read { db in
            let device = try XCTUnwrap(String.fetchOne(db, sql: "SELECT device_id FROM sync_state"))
            for table in ["habits", "water_logs", "focus_sessions"] {
                let row = try XCTUnwrap(Row.fetchOne(db, sql: "SELECT uuid, dirty, updated_at, updated_by FROM \(table)"))
                let uuid: String = row["uuid"]
                XCTAssertNotNil(uuid.range(of: pattern, options: .regularExpression), table)
                XCTAssertEqual(row["dirty"] as Int, 1, table)
                XCTAssertTrue((row["updated_at"] as String).hasSuffix("Z"), table)
                XCTAssertEqual(row["updated_by"] as String, device, table)
            }
        }
    }

    func testEditsMarkTheRowAgain() throws {
        let db = try IsletoDatabase.inMemory()
        let habits = HabitStore(database: db)
        let id = try XCTUnwrap(habits.create(HabitDefinition(name: "Ler"), at: today, calendar: calendar))
        // What the sync engine does after sending: clear dirty without touching the time.
        try db.write { try $0.execute(sql: "UPDATE habits SET dirty = 0") }
        XCTAssertEqual(try count(db, "SELECT dirty FROM habits"), 0, "clearing dirty does not mark it again")

        try habits.setArchived(id: id, true)
        XCTAssertEqual(try count(db, "SELECT dirty FROM habits"), 1)
    }

    func testDeletesLeaveTombstonesAndUndoingRemovesThem() throws {
        let db = try IsletoDatabase.inMemory()
        let store = IsletoStore(database: db)
        let id = try XCTUnwrap(store.habits.create(HabitDefinition(name: "Ler"), at: today, calendar: calendar))
        let day = Day(today, calendar: calendar)

        try store.habits.toggle(id: id, day: day)
        try store.habits.toggle(id: id, day: day)
        XCTAssertEqual(try count(db, "SELECT COUNT(*) FROM sync_tombstones WHERE tbl = 'habit_checks'"), 1, "unchecking leaves a tombstone")
        let row = try XCTUnwrap(db.read { try String.fetchOne($0, sql: "SELECT row FROM sync_tombstones") })
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(row.utf8)) as? [String: Any])
        XCTAssertEqual(json["day"] as? String, day.string)

        try store.habits.toggle(id: id, day: day)
        XCTAssertEqual(try count(db, "SELECT COUNT(*) FROM sync_tombstones WHERE tbl = 'habit_checks'"), 0, "checking again removes it")

        try store.water.add(at: today, calendar: calendar)
        XCTAssertTrue(try store.water.undoLast(on: today, calendar: calendar))
        XCTAssertEqual(try count(db, "SELECT COUNT(*) FROM sync_tombstones WHERE tbl = 'water_logs'"), 1)

        try store.habits.delete(id: id)
        XCTAssertEqual(try count(db, "SELECT COUNT(*) FROM sync_tombstones WHERE tbl = 'habits'"), 1)
        XCTAssertEqual(try count(db, "SELECT COUNT(*) FROM sync_tombstones WHERE tbl = 'habit_checks'"), 1)
    }

    func testApplyingRemoteRowsLeavesThemAlone() throws {
        let db = try IsletoDatabase.inMemory()
        try db.write { db in
            try db.execute(sql: "UPDATE sync_state SET applying = 1")
            try db.execute(sql: """
                INSERT INTO habits (uuid, name, created_at, updated_at, updated_by, dirty)
                VALUES ('aaaaaaaa-0000-4000-8000-000000000001', 'Remoto', '2026-11-18 09:00:00',
                        '2026-11-18T10:00:00.000Z', 'outro', 0)
                """)
            try db.execute(sql: "UPDATE sync_state SET applying = 0")
        }
        let row = try XCTUnwrap(db.read { try Row.fetchOne($0, sql: "SELECT dirty, updated_by FROM habits") })
        XCTAssertEqual(row["dirty"] as Int, 0)
        XCTAssertEqual(row["updated_by"] as String, "outro")
    }

    /// A database from before v6 gets uuids and is marked to be sent once.
    func testExistingRowsAreMarkedOnUpgrade() throws {
        let db = try DatabaseQueue()
        try db.writeWithoutTransaction { db in
            for sql in Schema.migrations.prefix(5) {
                try db.execute(sql: sql)
            }
            try db.execute(sql: "PRAGMA user_version = 5")
            try db.execute(sql: "INSERT INTO habits (name) VALUES ('Ler')")
            try db.execute(sql: "INSERT INTO habit_checks (habit_id, day) VALUES (1, '2026-11-17')")
            try Schema.migrate(db)
        }
        XCTAssertEqual(try count(db, "SELECT COUNT(*) FROM habits WHERE uuid IS NOT NULL AND dirty = 1"), 1)
        XCTAssertEqual(try count(db, "SELECT COUNT(*) FROM habit_checks WHERE updated_at <> '' AND dirty = 1"), 1)
        XCTAssertEqual(try count(db, "SELECT COUNT(*) FROM sync_state"), 1)
    }
}
