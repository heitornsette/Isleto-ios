import GRDB

/// Feasibility-test counter, shared by the app and the widget.
///
/// Stored in the desktop's `settings` key/value table, so the probe adds no table
/// that the desktop does not have.
public struct ProbeCounter: Sendable {
    public static let key = "probe_counter"

    private let database: DatabaseQueue

    public init(database: DatabaseQueue) {
        self.database = database
    }

    public func value() throws -> Int {
        try database.read { try Self.read($0) }
    }

    /// Adds one and returns the new value.
    @discardableResult
    public func increment() throws -> Int {
        try database.writeWithoutTransaction { db in
            var next = 0
            // IMMEDIATE: take the write lock before reading, so an increment from the
            // widget process and one from the app can never both read the same value.
            try db.inTransaction(.immediate) {
                next = try Self.read(db) + 1
                try Self.write(next, db)
                return .commit
            }
            return next
        }
    }

    public func reset() throws {
        try database.write { try Self.write(0, $0) }
    }

    private static func read(_ db: Database) throws -> Int {
        let text = try String.fetchOne(db, sql: "SELECT value FROM settings WHERE key = ?", arguments: [key])
        return text.flatMap { Int($0) } ?? 0
    }

    private static func write(_ value: Int, _ db: Database) throws {
        try db.execute(
            sql: """
            INSERT INTO settings (key, value) VALUES (?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value
            """,
            arguments: [key, String(value)]
        )
    }
}
