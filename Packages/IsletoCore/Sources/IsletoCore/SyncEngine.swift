import Foundation
import GRDB

/// Server side of the sync (isleto-cloud `sync_push` and `sync_pull`).
/// `pull` returns the JSON of `sync_pull`. The HTTP + login version comes with the
/// "Conectar à nuvem" screen; tests use an in-memory server.
public protocol SyncTransport: Sendable {
    func push(_ changes: [String: JSONValue]) async throws
    func pull(since: Int64, maxRows: Int) async throws -> JSONValue
}

public struct SyncReport: Equatable, Sendable {
    /// Rows received from the server.
    public var pulled = 0
    /// Received rows written locally (the others were older than the local version).
    public var applied = 0
    /// Local habits or categories joined with a remote one of the same name (first sync).
    public var merged = 0
    /// Rows sent to the server.
    public var pushed = 0

    public init() {}
}

public enum SyncError: LocalizedError {
    case invalidResponse(String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse(let detail): "Resposta inválida do servidor: \(detail)"
        }
    }
}

/// Exchanges changes between the local SQLite (migration v6) and the cloud. Same
/// algorithm as the desktop (`isleto/src/sync.rs`); see the isleto-cloud README.
///
/// One run:
/// 1. Pull every server change since the saved cursor, all pages, before applying anything
///    (a check can arrive in an earlier page than its habit).
/// 2. Apply them in one transaction, with `sync_state.applying` on so the triggers leave the
///    rows alone. A remote row wins when its (updated_at, updated_by) is greater than the
///    local row's, or than the local tombstone's. On the first sync, a remote habit or
///    category with the same name as a local one takes its place.
/// 3. Push the dirty rows and the tombstones, then clear only what was sent and did not
///    change meanwhile. Only tables the server knows (keys of the pull answer) are sent: rows
///    of a table added in a newer migration wait, dirty, until the server has it too.
public struct SyncEngine: Sendable {
    public static let pageSize = 1000
    static let maxPages = 10_000
    /// Every synced table, in the order rows are applied (parents first).
    public static let tables = [
        "habit_categories", "habits", "habit_category_links", "habit_checks", "water_logs", "focus_sessions",
        "exercises", "workout_plans", "workout_plan_exercises", "workouts", "workout_sets",
    ]

    private let database: DatabaseQueue

    public init(database: DatabaseQueue) {
        self.database = database
    }

    /// Runs one sync. Safe to call again after an error: nothing is lost, the next run resumes.
    @discardableResult
    public func sync(using transport: some SyncTransport) async throws -> SyncReport {
        var report = SyncReport()
        let cursor = try await database.read { try Int64.fetchOne($0, sql: "SELECT cursor FROM sync_state") ?? 0 }

        // 1. Pull every page.
        var batch: [String: [[String: JSONValue]]] = [:]
        var since = cursor
        var pages = 0
        var supported = Set<String>()
        while true {
            pages += 1
            guard pages <= Self.maxPages else { throw SyncError.invalidResponse("páginas demais") }
            let page = try await transport.pull(since: since, maxRows: Self.pageSize)
            for table in Self.tables {
                if page[table]?.arrayValue != nil {
                    supported.insert(table)
                }
                let rows = page[table]?.arrayValue?.compactMap(\.objectValue) ?? []
                report.pulled += rows.count
                batch[table, default: []].append(contentsOf: rows)
            }
            guard let next = page["cursor"]?.doubleValue else { throw SyncError.invalidResponse("sem cursor") }
            since = Int64(next)
            if page["has_more"]?.boolValue != true { break }
        }

        // 2. Apply.
        let rows = batch
        let newCursor = since
        let firstSync = cursor == 0
        let applied = try await database.write { db -> SyncReport in
            var partial = SyncReport()
            try db.execute(sql: "UPDATE sync_state SET applying = 1")
            try Self.applyUUIDRows(db, .categories, rows["habit_categories"] ?? [], firstSync: firstSync, &partial)
            try Self.applyUUIDRows(db, .habits, rows["habits"] ?? [], firstSync: firstSync, &partial)
            try Self.applyLinks(db, rows["habit_category_links"] ?? [], &partial)
            try Self.applyChecks(db, rows["habit_checks"] ?? [], &partial)
            try Self.applyUUIDRows(db, .water, rows["water_logs"] ?? [], firstSync: false, &partial)
            try Self.applyUUIDRows(db, .focus, rows["focus_sessions"] ?? [], firstSync: false, &partial)
            for table in [UUIDTable.exercises, .plans, .planExercises, .workouts, .sets] {
                try Self.applyUUIDRows(db, table, rows[table.name] ?? [], firstSync: false, &partial)
            }
            try db.execute(sql: "UPDATE sync_state SET applying = 0, cursor = ?", arguments: [newCursor])
            return partial
        }
        report.applied = applied.applied
        report.merged = applied.merged

        // 3. Push.
        let known = supported
        let (changes, sent) = try await database.read { try Self.collectChanges($0, supported: known) }
        if sent.count > 0 {
            try await transport.push(changes)
            report.pushed = sent.count
            try await database.write { try sent.clear($0) }
        }
        try await database.write {
            try $0.execute(sql: "UPDATE sync_state SET last_sync = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')")
        }
        return report
    }

    // MARK: Times and versions

    /// "YYYY-MM-DDTHH:MM:SS.mmmZ", the format of the local triggers. The server returns
    /// timestamps like "2026-11-18T10:00:00.123456+00:00"; both must compare as text.
    /// Text in another offset is returned unchanged (Supabase always answers in UTC).
    public static func canonicalTime(_ text: String) -> String {
        let text = text.trimmingCharacters(in: .whitespaces)
        let characters = Array(text)
        guard characters.count >= 19 else { return text }
        var base = String(characters[0..<19])
        if characters[10] == " " {
            base = String(characters[0..<10]) + "T" + String(characters[11..<19])
        }
        var rest = characters[19...]
        var fraction = ""
        if rest.first == "." {
            rest = rest.dropFirst()
            while let character = rest.first, character.isASCII, character.isNumber {
                fraction.append(character)
                rest = rest.dropFirst()
            }
        }
        guard ["", "Z", "+00:00", "+00", "+0000"].contains(String(rest)) else { return text }
        var millis = String(fraction.prefix(3))
        while millis.count < 3 { millis += "0" }
        return base + "." + millis + "Z"
    }

    static func version(_ row: [String: JSONValue]) -> (String, String) {
        (canonicalTime(row["updated_at"]?.stringValue ?? ""), row["updated_by"]?.stringValue ?? "")
    }

    private static func text(_ row: [String: JSONValue], _ key: String) throws -> String {
        guard let value = row[key]?.stringValue else { throw SyncError.invalidResponse("campo \(key) ausente") }
        return value
    }

    private static func tombstoneVersion(_ db: Database, _ table: String, _ key: String) throws -> (String, String)? {
        try Row.fetchOne(
            db, sql: "SELECT deleted_at, deleted_by FROM sync_tombstones WHERE tbl = ? AND key = ?", arguments: [table, key]
        ).map { ($0["deleted_at"] as String, $0["deleted_by"] as String) }
    }

    // MARK: Tables

    enum Kind: Sendable, Equatable {
        case text, real, int, bool
        /// Local id of a row of that table; its uuid on the server. A row whose parent is
        /// missing here (deleted, or never received) is skipped.
        case ref(String)
        /// Same, but may be null (and is set to null when the parent is missing).
        case optionalRef(String)

        var parent: String? {
            switch self {
            case .ref(let table), .optionalRef(let table): table
            default: nil
            }
        }
    }

    /// A table whose rows have their own uuid.
    struct UUIDTable: Sendable {
        let name: String
        let fields: [(name: String, kind: Kind)]
        /// Children removed with the row, so a missing child tombstone leaves no orphans.
        let children: [String]
        let mergeByName: Bool

        static let habits = UUIDTable(
            name: "habits",
            fields: [
                ("name", .text), ("created_at", .text), ("description", .text), ("icon", .text), ("color", .text),
                ("kind", .text), ("schedule", .text), ("record", .text), ("target", .real), ("unit", .text),
                ("reminders", .text), ("archived", .bool), ("sort_order", .int),
            ],
            children: [
                "DELETE FROM habit_checks WHERE habit_id = ?",
                "DELETE FROM habit_category_links WHERE habit_id = ?",
            ],
            mergeByName: true
        )
        static let categories = UUIDTable(
            name: "habit_categories",
            fields: [("name", .text), ("created_at", .text)],
            children: ["DELETE FROM habit_category_links WHERE category_id = ?"],
            mergeByName: true
        )
        static let water = UUIDTable(
            name: "water_logs", fields: [("logged_at", .text), ("ml", .int)], children: [], mergeByName: false
        )
        static let focus = UUIDTable(
            name: "focus_sessions", fields: [("finished_at", .text), ("minutes", .int)], children: [], mergeByName: false
        )
        static let exercises = UUIDTable(
            name: "exercises",
            fields: [("name", .text), ("muscle", .text), ("notes", .text), ("archived", .bool), ("created_at", .text)],
            children: [
                "DELETE FROM workout_plan_exercises WHERE exercise_id = ?",
                "DELETE FROM workout_sets WHERE exercise_id = ?",
            ],
            mergeByName: false
        )
        static let plans = UUIDTable(
            name: "workout_plans",
            fields: [("name", .text), ("notes", .text), ("sort_order", .int), ("archived", .bool), ("created_at", .text)],
            children: [
                "DELETE FROM workout_plan_exercises WHERE plan_id = ?",
                "UPDATE workouts SET plan_id = NULL WHERE plan_id = ?",
            ],
            mergeByName: false
        )
        static let planExercises = UUIDTable(
            name: "workout_plan_exercises",
            fields: [
                ("plan_id", .ref("workout_plans")), ("exercise_id", .ref("exercises")), ("position", .int),
                ("sets", .int), ("reps", .text), ("rest_seconds", .int),
            ],
            children: [],
            mergeByName: false
        )
        static let workouts = UUIDTable(
            name: "workouts",
            fields: [
                ("plan_id", .optionalRef("workout_plans")), ("name", .text), ("started_at", .text),
                ("finished_at", .text), ("notes", .text),
            ],
            children: ["DELETE FROM workout_sets WHERE workout_id = ?"],
            mergeByName: false
        )
        static let sets = UUIDTable(
            name: "workout_sets",
            fields: [
                ("workout_id", .ref("workouts")), ("exercise_id", .ref("exercises")), ("position", .int),
                ("set_number", .int), ("reps", .int), ("weight", .real), ("done", .bool), ("done_at", .text),
            ],
            children: [],
            mergeByName: false
        )

        /// Every table whose rows have their own uuid.
        static let all: [UUIDTable] = [.habits, .categories, .water, .focus, .exercises, .plans, .planExercises, .workouts, .sets]
    }

    private static func sqlValue(_ kind: Kind, _ value: JSONValue?) -> DatabaseValue {
        switch (kind, value) {
        case (.text, .string(let text)?): text.databaseValue
        case (.text, _): "".databaseValue
        case (.real, .number(let number)?): number.databaseValue
        case (.int, .number(let number)?): Int64(number).databaseValue
        case (.bool, .bool(let flag)?): Int64(flag ? 1 : 0).databaseValue
        case (.bool, .number(let number)?): Int64(number != 0 ? 1 : 0).databaseValue
        case (.ref, _), (.optionalRef, _): .null
        default: Int64(0).databaseValue
        }
    }

    private static func jsonValue(_ kind: Kind, _ value: DatabaseValue) -> JSONValue {
        switch value.storage {
        case .int64(let number): kind == .bool ? .bool(number != 0) : .number(Double(number))
        case .double(let number): .number(number)
        case .string(let text): .string(text)
        case .null, .blob: .null
        }
    }

    // MARK: Applying remote rows

    private static func applyUUIDRows(
        _ db: Database,
        _ table: UUIDTable,
        _ rows: [[String: JSONValue]],
        firstSync: Bool,
        _ report: inout SyncReport
    ) throws {
        let remoteIDs = Set(rows.compactMap { $0["id"]?.stringValue })
        for row in rows {
            let uuid = try text(row, "id")
            let remote = version(row)
            let deleted = row["deleted"]?.boolValue ?? false

            var local = try Row.fetchOne(
                db, sql: "SELECT id, updated_at, updated_by FROM \(table.name) WHERE uuid = ?", arguments: [uuid]
            ).map { (id: $0["id"] as Int64, at: $0["updated_at"] as String, by: $0["updated_by"] as String) }

            // First sync: a local habit or category with the same name becomes the remote one.
            if local == nil, firstSync, table.mergeByName, !deleted, let name = row["name"]?.stringValue {
                let candidates = try Row.fetchAll(
                    db,
                    sql: "SELECT id, uuid, updated_at, updated_by FROM \(table.name) WHERE lower(trim(name)) = lower(trim(?)) ORDER BY id",
                    arguments: [name]
                )
                if let match = candidates.first(where: { candidate in
                    (candidate["uuid"] as String?).map { !remoteIDs.contains($0) } ?? true
                }) {
                    let id: Int64 = match["id"]
                    try db.execute(sql: "UPDATE \(table.name) SET uuid = ? WHERE id = ?", arguments: [uuid, id])
                    local = (id: id, at: match["updated_at"], by: match["updated_by"])
                    report.merged += 1
                }
            }

            let localVersion = try local.map { ($0.at, $0.by) } ?? tombstoneVersion(db, table.name, uuid)
            if let localVersion, localVersion >= remote { continue }

            // References arrive as uuids: use the local ids.
            var values: [DatabaseValue] = []
            var missingParent = false
            for field in table.fields {
                guard let parent = field.kind.parent else {
                    values.append(sqlValue(field.kind, row[field.name]))
                    continue
                }
                var id: Int64?
                if let parentUUID = row[field.name]?.stringValue {
                    id = try localID(db, parent, parentUUID)
                }
                if id == nil, case .ref = field.kind {
                    missingParent = true
                }
                values.append(id?.databaseValue ?? .null)
            }
            // The parent was deleted here, or never reached this device: nothing to attach to.
            if missingParent, !deleted { continue }
            report.applied += 1

            if deleted {
                if let local {
                    for child in table.children {
                        try db.execute(sql: child, arguments: [local.id])
                    }
                    try db.execute(sql: "DELETE FROM \(table.name) WHERE id = ?", arguments: [local.id])
                }
            } else {
                values.append(remote.0.databaseValue)
                values.append(remote.1.databaseValue)
                let columns = table.fields.map(\.name)
                if let local {
                    values.append(local.id.databaseValue)
                    let assignments = columns.map { "\($0) = ?" }.joined(separator: ", ")
                    try db.execute(
                        sql: "UPDATE \(table.name) SET \(assignments), updated_at = ?, updated_by = ?, dirty = 0 WHERE id = ?",
                        arguments: StatementArguments(values)
                    )
                } else {
                    values.insert(uuid.databaseValue, at: 0)
                    let placeholders = Array(repeating: "?", count: columns.count + 3).joined(separator: ", ")
                    try db.execute(
                        sql: """
                        INSERT INTO \(table.name) (uuid, \(columns.joined(separator: ", ")), updated_at, updated_by, dirty)
                        VALUES (\(placeholders), 0)
                        """,
                        arguments: StatementArguments(values)
                    )
                }
            }
            try db.execute(sql: "DELETE FROM sync_tombstones WHERE tbl = ? AND key = ?", arguments: [table.name, uuid])
        }
    }

    private static func localID(_ db: Database, _ table: String, _ uuid: String) throws -> Int64? {
        try Int64.fetchOne(db, sql: "SELECT id FROM \(table) WHERE uuid = ?", arguments: [uuid])
    }

    private static func applyChecks(_ db: Database, _ rows: [[String: JSONValue]], _ report: inout SyncReport) throws {
        for row in rows {
            let habitUUID = try text(row, "habit_id")
            let day = try text(row, "day")
            // The habit was deleted here, or never reached this device: nothing to attach to.
            guard let habitID = try localID(db, "habits", habitUUID) else { continue }
            let key = "\(habitUUID)|\(day)"
            let remote = version(row)
            let local = try Row.fetchOne(
                db, sql: "SELECT updated_at, updated_by FROM habit_checks WHERE habit_id = ? AND day = ?", arguments: [habitID, day]
            ).map { ($0["updated_at"] as String, $0["updated_by"] as String) }
            let localVersion = try local ?? tombstoneVersion(db, "habit_checks", key)
            if let localVersion, localVersion >= remote { continue }
            report.applied += 1
            if row["deleted"]?.boolValue == true {
                try db.execute(sql: "DELETE FROM habit_checks WHERE habit_id = ? AND day = ?", arguments: [habitID, day])
            } else {
                try db.execute(
                    sql: """
                    INSERT INTO habit_checks (habit_id, day, value, updated_at, updated_by, dirty)
                    VALUES (?, ?, ?, ?, ?, 0)
                    ON CONFLICT (habit_id, day) DO UPDATE SET value = excluded.value,
                        updated_at = excluded.updated_at, updated_by = excluded.updated_by, dirty = 0
                    """,
                    arguments: [habitID, day, row["value"]?.doubleValue ?? 1, remote.0, remote.1]
                )
            }
            try db.execute(sql: "DELETE FROM sync_tombstones WHERE tbl = 'habit_checks' AND key = ?", arguments: [key])
        }
    }

    private static func applyLinks(_ db: Database, _ rows: [[String: JSONValue]], _ report: inout SyncReport) throws {
        for row in rows {
            let habitUUID = try text(row, "habit_id")
            let categoryUUID = try text(row, "category_id")
            guard let habitID = try localID(db, "habits", habitUUID),
                  let categoryID = try localID(db, "habit_categories", categoryUUID)
            else { continue }
            let key = "\(habitUUID)|\(categoryUUID)"
            let remote = version(row)
            let local = try Row.fetchOne(
                db,
                sql: "SELECT updated_at, updated_by FROM habit_category_links WHERE habit_id = ? AND category_id = ?",
                arguments: [habitID, categoryID]
            ).map { ($0["updated_at"] as String, $0["updated_by"] as String) }
            let localVersion = try local ?? tombstoneVersion(db, "habit_category_links", key)
            if let localVersion, localVersion >= remote { continue }
            report.applied += 1
            if row["deleted"]?.boolValue == true {
                try db.execute(
                    sql: "DELETE FROM habit_category_links WHERE habit_id = ? AND category_id = ?",
                    arguments: [habitID, categoryID]
                )
            } else {
                try db.execute(
                    sql: """
                    INSERT INTO habit_category_links (habit_id, category_id, updated_at, updated_by, dirty)
                    VALUES (?, ?, ?, ?, 0)
                    ON CONFLICT (habit_id, category_id) DO UPDATE SET
                        updated_at = excluded.updated_at, updated_by = excluded.updated_by, dirty = 0
                    """,
                    arguments: [habitID, categoryID, remote.0, remote.1]
                )
            }
            try db.execute(sql: "DELETE FROM sync_tombstones WHERE tbl = 'habit_category_links' AND key = ?", arguments: [key])
        }
    }

    // MARK: Collecting local changes

    /// What was sent, to clear it afterwards only if it did not change meanwhile.
    struct Sent: Sendable {
        struct SentRow: Sendable {
            let table: String
            let rowid: Int64
            let updatedAt: String
        }

        struct SentTombstone: Sendable {
            let table: String
            let key: String
            let deletedAt: String
        }

        var rows: [SentRow] = []
        var tombstones: [SentTombstone] = []

        var count: Int { rows.count + tombstones.count }

        func clear(_ db: Database) throws {
            for row in rows {
                try db.execute(
                    sql: "UPDATE \(row.table) SET dirty = 0 WHERE rowid = ? AND updated_at = ?",
                    arguments: [row.rowid, row.updatedAt]
                )
            }
            for tombstone in tombstones {
                try db.execute(
                    sql: "DELETE FROM sync_tombstones WHERE tbl = ? AND key = ? AND deleted_at = ?",
                    arguments: [tombstone.table, tombstone.key, tombstone.deletedAt]
                )
            }
        }
    }

    static func collectChanges(
        _ db: Database,
        supported: Set<String> = Set(tables)
    ) throws -> ([String: JSONValue], Sent) {
        var changes: [String: [JSONValue]] = Dictionary(
            uniqueKeysWithValues: tables.filter(supported.contains).map { ($0, []) }
        )
        var sent = Sent()

        for table in UUIDTable.all where supported.contains(table.name) {
            // References leave as the parent's uuid.
            let columns = table.fields.map { field in
                field.kind.parent.map { "(SELECT uuid FROM \($0) WHERE id = t.\(field.name)) AS \(field.name)" }
                    ?? "t.\(field.name) AS \(field.name)"
            }.joined(separator: ", ")
            let rows = try Row.fetchAll(
                db,
                // "AS rowid": without it SQLite names the column after the INTEGER PRIMARY KEY ("id").
                sql: "SELECT t.rowid AS rowid, t.uuid, t.updated_at, t.updated_by, \(columns) FROM \(table.name) t WHERE t.dirty = 1 AND t.uuid IS NOT NULL"
            )
            for row in rows {
                let updatedAt: String = row["updated_at"]
                var item: [String: JSONValue] = [
                    "id": .string(row["uuid"]),
                    "updated_at": .string(updatedAt),
                    "updated_by": .string(row["updated_by"]),
                    "deleted": .bool(false),
                ]
                for field in table.fields {
                    item[field.name] = jsonValue(field.kind, row[field.name] as DatabaseValue)
                }
                changes[table.name, default: []].append(.object(item))
                sent.rows.append(.init(table: table.name, rowid: row["rowid"], updatedAt: updatedAt))
            }
        }

        for row in try Row.fetchAll(db, sql: """
            SELECT c.rowid AS rowid, h.uuid AS habit_uuid, c.day, c.value, c.updated_at, c.updated_by
            FROM habit_checks c JOIN habits h ON h.id = c.habit_id
            WHERE c.dirty = 1 AND h.uuid IS NOT NULL
            """) where supported.contains("habit_checks") {
            let updatedAt: String = row["updated_at"]
            changes["habit_checks", default: []].append(.object([
                "habit_id": .string(row["habit_uuid"]),
                "day": .string(row["day"]),
                "value": .number(row["value"]),
                "updated_at": .string(updatedAt),
                "updated_by": .string(row["updated_by"]),
                "deleted": .bool(false),
            ]))
            sent.rows.append(.init(table: "habit_checks", rowid: row["rowid"], updatedAt: updatedAt))
        }

        for row in try Row.fetchAll(db, sql: """
            SELECT l.rowid AS rowid, h.uuid AS habit_uuid, k.uuid AS category_uuid, l.updated_at, l.updated_by
            FROM habit_category_links l
            JOIN habits h ON h.id = l.habit_id
            JOIN habit_categories k ON k.id = l.category_id
            WHERE l.dirty = 1 AND h.uuid IS NOT NULL AND k.uuid IS NOT NULL
            """) where supported.contains("habit_category_links") {
            let updatedAt: String = row["updated_at"]
            changes["habit_category_links", default: []].append(.object([
                "habit_id": .string(row["habit_uuid"]),
                "category_id": .string(row["category_uuid"]),
                "updated_at": .string(updatedAt),
                "updated_by": .string(row["updated_by"]),
                "deleted": .bool(false),
            ]))
            sent.rows.append(.init(table: "habit_category_links", rowid: row["rowid"], updatedAt: updatedAt))
        }

        for row in try Row.fetchAll(db, sql: "SELECT tbl, key, row, deleted_at, deleted_by FROM sync_tombstones") {
            let table: String = row["tbl"]
            let text: String = row["row"]
            guard changes[table] != nil,
                  case .object(var item)? = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
            else { continue }
            // SQLite's json_object() writes the 0/1 of the column; the server wants a boolean.
            for field in UUIDTable.all.first(where: { $0.name == table })?.fields ?? [] where field.kind == .bool {
                item[field.name] = .bool((item[field.name]?.doubleValue ?? 0) != 0)
            }
            let deletedAt: String = row["deleted_at"]
            item["updated_at"] = .string(deletedAt)
            item["updated_by"] = .string(row["deleted_by"])
            item["deleted"] = .bool(true)
            changes[table, default: []].append(.object(item))
            sent.tombstones.append(.init(table: table, key: row["key"], deletedAt: deletedAt))
        }

        return (changes.mapValues { .array($0) }, sent)
    }
}
