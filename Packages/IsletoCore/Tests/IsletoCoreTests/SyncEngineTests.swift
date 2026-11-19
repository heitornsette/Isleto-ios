import Foundation
import GRDB
import XCTest
@testable import IsletoCore

/// In-memory stand-in for isleto-cloud: same rules as sync_push / sync_pull.
actor FakeServer: SyncTransport {
    private var rows: [String: (table: String, row: [String: JSONValue], version: Int64)] = [:]
    private var version: Int64 = 0
    private var pageSize: Int?
    /// Tables of an older server; nil = all of them.
    private var known: [String]?
    private(set) var pushes = 0

    func setPageSize(_ size: Int?) { pageSize = size }
    func setKnownTables(_ tables: [String]?) { known = tables }

    func row(_ table: String) -> [String: JSONValue]? { rows.values.first { $0.table == table }?.row }

    func count(_ table: String) -> Int { rows.values.filter { $0.table == table }.count }

    private static func key(_ table: String, _ row: [String: JSONValue]) -> String {
        let field = { (name: String) in row[name]?.stringValue ?? "" }
        switch table {
        case "habit_checks": return "\(table)/\(field("habit_id"))|\(field("day"))"
        case "habit_category_links": return "\(table)/\(field("habit_id"))|\(field("category_id"))"
        default: return "\(table)/\(field("id"))"
        }
    }

    func push(_ changes: [String: JSONValue]) async throws {
        pushes += 1
        for table in SyncEngine.tables {
            guard let list = changes[table]?.arrayValue else { continue }
            if let known, !known.contains(table) {
                throw SyncError.invalidResponse("tabela desconhecida: \(table)")
            }
            for case .object(let row) in list {
                let key = Self.key(table, row)
                if let stored = rows[key], SyncEngine.version(row) <= SyncEngine.version(stored.row) { continue }
                version += 1
                rows[key] = (table, row, version)
            }
        }
    }

    func pull(since: Int64, maxRows: Int) async throws -> JSONValue {
        let limit = pageSize ?? maxRows
        let found = rows.values.filter { $0.version > since }.sorted { $0.version < $1.version }
        let tables = SyncEngine.tables.filter { known?.contains($0) ?? true }
        var page: [String: [JSONValue]] = Dictionary(uniqueKeysWithValues: tables.map { ($0, []) })
        var cursor = since
        for entry in found.prefix(limit) {
            page[entry.table, default: []].append(.object(entry.row))
            cursor = max(cursor, entry.version)
        }
        var result = page.mapValues { JSONValue.array($0) }
        result["cursor"] = .number(Double(cursor))
        result["has_more"] = .bool(found.count > limit)
        return .object(result)
    }
}

struct OfflineServer: SyncTransport {
    struct Offline: Error {}
    func push(_ changes: [String: JSONValue]) async throws { throw Offline() }
    func pull(since: Int64, maxRows: Int) async throws -> JSONValue {
        var page = Dictionary(uniqueKeysWithValues: SyncEngine.tables.map { ($0, JSONValue.array([])) })
        page["cursor"] = .number(Double(since))
        page["has_more"] = .bool(false)
        return .object(page)
    }
}

/// Same scenarios as the desktop tests (`isleto/src/sync.rs`).
final class SyncEngineTests: XCTestCase {
    private func device() throws -> DatabaseQueue { try IsletoDatabase.inMemory() }

    private func exec(_ db: DatabaseQueue, _ sql: String, _ arguments: StatementArguments = []) throws {
        try db.write { try $0.execute(sql: sql, arguments: arguments) }
    }

    private func count(_ db: DatabaseQueue, _ sql: String) throws -> Int {
        try db.read { try Int.fetchOne($0, sql: sql) ?? -1 }
    }

    private func names(_ db: DatabaseQueue) throws -> [String] {
        try db.read { try String.fetchAll($0, sql: "SELECT name FROM habits ORDER BY name") }
    }

    @discardableResult
    private func addHabit(_ db: DatabaseQueue, _ name: String) throws -> Int64 {
        try db.write { db in
            try db.execute(sql: "INSERT INTO habits (name) VALUES (?)", arguments: [name])
            return db.lastInsertedRowID
        }
    }

    private func check(_ db: DatabaseQueue, _ habit: Int64, _ day: String) throws {
        try exec(db, "INSERT INTO habit_checks (habit_id, day) VALUES (?, ?)", [habit, day])
    }

    /// Edits in tests get explicit (future) times, so "newest wins" does not depend on the clock.
    private func setTime(_ db: DatabaseQueue, _ table: String, _ id: Int64, _ time: String) throws {
        try exec(db, "UPDATE \(table) SET updated_at = ? WHERE id = ?", [time, id])
    }

    @discardableResult
    private func sync(_ db: DatabaseQueue, _ server: some SyncTransport) async throws -> SyncReport {
        try await SyncEngine(database: db).sync(using: server)
    }

    func testCanonicalTimeNormalizesServerTimestamps() {
        XCTAssertEqual(SyncEngine.canonicalTime("2026-11-18T10:00:00.123456+00:00"), "2026-11-18T10:00:00.123Z")
        XCTAssertEqual(SyncEngine.canonicalTime("2026-11-18T10:00:00+00:00"), "2026-11-18T10:00:00.000Z")
        XCTAssertEqual(SyncEngine.canonicalTime("2026-11-18 10:00:00.5Z"), "2026-11-18T10:00:00.500Z")
        XCTAssertEqual(SyncEngine.canonicalTime("2026-11-18T10:00:00.123Z"), "2026-11-18T10:00:00.123Z")
        XCTAssertEqual(SyncEngine.canonicalTime("2026-11-18T10:00:00-03:00"), "2026-11-18T10:00:00-03:00")
        XCTAssertEqual(SyncEngine.canonicalTime("bad"), "bad")
    }

    func testFirstSyncUploadsEverythingAndClearsIt() async throws {
        let server = FakeServer()
        let phone = try device()
        let habit = try addHabit(phone, "Ler")
        try check(phone, habit, "2026-11-17")
        try exec(phone, "INSERT INTO water_logs (ml) VALUES (250)")
        try exec(phone, "INSERT INTO focus_sessions (minutes) VALUES (25)")
        try exec(phone, "INSERT INTO habit_categories (name) VALUES ('Saúde')")
        try exec(phone, "INSERT INTO habit_category_links (habit_id, category_id) VALUES (1, 1)")

        let report = try await sync(phone, server)
        XCTAssertEqual(report.pushed, 6)
        for table in SyncEngine.tables {
            let onServer = await server.count(table)
            XCTAssertEqual(onServer, 1, table)
            XCTAssertEqual(try count(phone, "SELECT COUNT(*) FROM \(table) WHERE dirty = 1"), 0, table)
        }
        let second = try await sync(phone, server)
        XCTAssertEqual(second.pushed, 0, "nothing new, nothing sent")
        let pushes = await server.pushes
        XCTAssertEqual(pushes, 1)
    }

    func testChangesTravelBetweenTwoDevices() async throws {
        let server = FakeServer()
        let phone = try device()
        let desktop = try device()
        let habit = try addHabit(phone, "Ler")
        try check(phone, habit, "2026-11-17")
        try exec(phone, "INSERT INTO water_logs (ml, logged_at) VALUES (500, '2026-11-17 08:00:00')")
        try await sync(phone, server)

        let report = try await sync(desktop, server)
        XCTAssertEqual(report.pulled, 3)
        XCTAssertEqual(try names(desktop), ["Ler"])
        XCTAssertEqual(try count(desktop, "SELECT COUNT(*) FROM habits h JOIN habit_checks c ON c.habit_id = h.id"), 1)
        XCTAssertEqual(try count(desktop, "SELECT ml FROM water_logs"), 500)
        XCTAssertEqual(try count(desktop, "SELECT COUNT(*) FROM habits WHERE dirty = 1"), 0, "received rows are not sent back")
        let again = try await sync(desktop, server)
        XCTAssertEqual(again.pushed, 0)

        try exec(desktop, "UPDATE habits SET name = 'Ler 20'")
        try exec(desktop, "DELETE FROM habit_checks")
        try await sync(desktop, server)
        try await sync(phone, server)
        XCTAssertEqual(try names(phone), ["Ler 20"])
        XCTAssertEqual(try count(phone, "SELECT COUNT(*) FROM habit_checks"), 0, "the uncheck reached the phone")
        XCTAssertEqual(try count(phone, "SELECT COUNT(*) FROM sync_tombstones"), 0)

        try exec(phone, "DELETE FROM habits")
        try await sync(phone, server)
        try await sync(desktop, server)
        XCTAssertEqual(try names(desktop), [])
    }

    func testTheNewestEditWinsWhateverTheSyncOrder() async throws {
        let server = FakeServer()
        let phone = try device()
        let desktop = try device()
        try addHabit(phone, "Ler")
        try await sync(phone, server)
        try await sync(desktop, server)

        try exec(phone, "UPDATE habits SET name = 'Telefone'")
        try setTime(phone, "habits", 1, "2099-01-01T10:00:00.000Z")
        try exec(desktop, "UPDATE habits SET name = 'Desktop'")
        try setTime(desktop, "habits", 1, "2099-01-01T11:00:00.000Z")
        try await sync(desktop, server)
        try await sync(phone, server)
        try await sync(desktop, server)
        XCTAssertEqual(try names(phone), ["Desktop"])
        XCTAssertEqual(try names(desktop), ["Desktop"])
    }

    func testANewerEditBringsBackADeletedRow() async throws {
        let server = FakeServer()
        let phone = try device()
        let desktop = try device()
        try addHabit(phone, "Ler")
        try await sync(phone, server)
        try await sync(desktop, server)

        try exec(phone, "DELETE FROM habits")
        try exec(phone, "UPDATE sync_tombstones SET deleted_at = '2099-01-01T10:00:00.000Z'")
        try exec(desktop, "UPDATE habits SET name = 'Ler mais'")
        try setTime(desktop, "habits", 1, "2099-01-01T11:00:00.000Z")
        try await sync(phone, server)
        try await sync(desktop, server)
        try await sync(phone, server)
        XCTAssertEqual(try names(phone), ["Ler mais"], "the later edit wins over the earlier delete")
        XCTAssertEqual(try names(desktop), ["Ler mais"])
    }

    func testFirstSyncJoinsHabitsWithTheSameName() async throws {
        let server = FakeServer()
        let phone = try device()
        let desktop = try device()
        let onPhone = try addHabit(phone, "Ler")
        try check(phone, onPhone, "2026-11-16")
        try await sync(phone, server)

        let onDesktop = try addHabit(desktop, "ler ")
        try check(desktop, onDesktop, "2026-11-17")
        try addHabit(desktop, "Só no desktop")
        let report = try await sync(desktop, server)
        XCTAssertEqual(report.merged, 1)
        XCTAssertEqual(try count(desktop, "SELECT COUNT(*) FROM habits"), 2, "no duplicate")
        XCTAssertEqual(try count(desktop, "SELECT COUNT(*) FROM habit_checks"), 2, "both days on one habit")

        try await sync(phone, server)
        XCTAssertEqual(try count(phone, "SELECT COUNT(*) FROM habits"), 2)
        XCTAssertEqual(try count(phone, "SELECT COUNT(*) FROM habit_checks WHERE habit_id = 1"), 2)
        let onServer = await server.count("habits")
        XCTAssertEqual(onServer, 2)
    }

    func testSmallPagesAndChecksBeforeTheirHabitStillApply() async throws {
        let server = FakeServer()
        let phone = try device()
        let habit = try addHabit(phone, "Ler")
        for day in ["2026-11-14", "2026-11-15", "2026-11-16"] {
            try check(phone, habit, day)
        }
        try await sync(phone, server)
        try exec(phone, "UPDATE habits SET name = 'Ler 20'")
        try await sync(phone, server)

        await server.setPageSize(1)
        let desktop = try device()
        let report = try await sync(desktop, server)
        XCTAssertEqual(report.pulled, 4)
        XCTAssertEqual(try names(desktop), ["Ler 20"])
        XCTAssertEqual(try count(desktop, "SELECT COUNT(*) FROM habit_checks"), 3)
    }

    func testAFailedPushKeepsEverythingForTheNextRun() async throws {
        let phone = try device()
        try addHabit(phone, "Ler")
        try exec(phone, "DELETE FROM habits")
        try addHabit(phone, "Correr")
        do {
            try await sync(phone, OfflineServer())
            XCTFail("the push should fail")
        } catch is OfflineServer.Offline {
        }
        XCTAssertEqual(try count(phone, "SELECT COUNT(*) FROM habits WHERE dirty = 1"), 1)
        XCTAssertEqual(try count(phone, "SELECT COUNT(*) FROM sync_tombstones"), 1)
        XCTAssertEqual(try count(phone, "SELECT applying FROM sync_state"), 0)
    }

    /// The stores keep working after a sync: what the screens do still reaches the server.
    func testStoreChangesAfterASyncAreSentNext() async throws {
        let server = FakeServer()
        let db = try device()
        let store = IsletoStore(database: db)
        try store.habits.create(HabitDefinition(name: "Ler"))
        try await sync(db, server)
        let id = try XCTUnwrap(store.habits.list().first?.id)
        try store.habits.toggle(id: id, day: Day(.now))
        try store.water.add()
        let report = try await sync(db, server)
        XCTAssertEqual(report.pushed, 2)
    }

    func testWorkoutsTravelWithTheirReferences() async throws {
        let server = FakeServer()
        let phone = try device()
        let desktop = try device()
        // The desktop already has a row, so local ids differ between the two devices.
        try exec(desktop, "INSERT INTO exercises (name) VALUES ('Remada')")
        try exec(phone, """
            INSERT INTO exercises (name, muscle) VALUES ('Supino', 'peito');
            INSERT INTO workout_plans (name) VALUES ('Treino A');
            INSERT INTO workout_plan_exercises (plan_id, exercise_id, sets, reps) VALUES (1, 1, 4, '8-12');
            INSERT INTO workouts (plan_id, name, started_at, finished_at)
                VALUES (1, 'Treino A', '2026-11-19 07:00:00', '2026-11-19 08:00:00');
            INSERT INTO workout_sets (workout_id, exercise_id, set_number, reps, weight, done) VALUES (1, 1, 1, 10, 42.5, 1);
            INSERT INTO workout_sets (workout_id, exercise_id, set_number, reps, weight, done) VALUES (1, 1, 2, 8, 45, 1);
            """)
        let first = try await sync(phone, server)
        XCTAssertEqual(first.pushed, 6)
        try await sync(desktop, server)

        XCTAssertEqual(try count(desktop, """
            SELECT COUNT(*) FROM workout_sets s
            JOIN workouts w ON w.id = s.workout_id
            JOIN workout_plans p ON p.id = w.plan_id
            JOIN exercises e ON e.id = s.exercise_id
            WHERE e.name = 'Supino' AND p.name = 'Treino A' AND s.done = 1
            """), 2, "sets point to the local ids of their workout and exercise")
        XCTAssertEqual(try count(desktop, "SELECT CAST(SUM(weight) * 10 AS INTEGER) FROM workout_sets"), 875)
        let pushedSet = await server.row("workout_sets")
        XCTAssertEqual(pushedSet?["done"], .bool(true), "booleans leave as booleans")

        // Deleting the plan keeps the workout, without a plan, on both devices.
        try exec(phone, "DELETE FROM workout_plans")
        try await sync(phone, server)
        try await sync(desktop, server)
        XCTAssertEqual(try count(desktop, "SELECT COUNT(*) FROM workout_plan_exercises"), 0)
        XCTAssertEqual(try count(desktop, "SELECT COUNT(*) FROM workouts WHERE plan_id IS NULL"), 1)

        // Deleting the workout cascades to its sets (foreign keys are on); the desktop follows.
        try exec(phone, "DELETE FROM workouts")
        XCTAssertEqual(try count(phone, "SELECT COUNT(*) FROM sync_tombstones WHERE tbl = 'workout_sets'"), 2)
        try await sync(phone, server)
        try await sync(desktop, server)
        XCTAssertEqual(try count(desktop, "SELECT COUNT(*) FROM workout_sets"), 0)
        XCTAssertEqual(try count(desktop, "SELECT COUNT(*) FROM exercises"), 2)
        let last = try await sync(desktop, server)
        XCTAssertEqual(last.pushed, 0, "applied deletes are not sent back")
    }

    func testRowsOfATableTheServerLacksWaitForIt() async throws {
        let server = FakeServer()
        await server.setKnownTables(Array(SyncEngine.tables.prefix(6)))
        let phone = try device()
        try addHabit(phone, "Ler")
        try exec(phone, "INSERT INTO exercises (name) VALUES ('Supino')")
        let before = try await sync(phone, server)
        XCTAssertEqual(before.pushed, 1, "only the habit")
        XCTAssertEqual(try count(phone, "SELECT COUNT(*) FROM exercises WHERE dirty = 1"), 1)

        await server.setKnownTables(nil)
        let after = try await sync(phone, server)
        XCTAssertEqual(after.pushed, 1)
        XCTAssertEqual(try count(phone, "SELECT COUNT(*) FROM exercises WHERE dirty = 1"), 0)
    }
}
