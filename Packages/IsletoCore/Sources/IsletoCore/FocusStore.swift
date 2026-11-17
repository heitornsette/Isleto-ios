import Foundation
import GRDB

/// A running focus session.
public struct ActiveFocus: Codable, Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let minutes: Int

    public init(start: Date, end: Date, minutes: Int) {
        self.start = start
        self.end = end
        self.minutes = minutes
    }

    public var range: ClosedRange<Date> { start...max(start, end) }
}

/// Focus (pomodoro) sessions.
///
/// The app can be closed when a session ends, so the running session is saved
/// (in the desktop's `settings` table, key `focus_active`) and "settled" the next
/// time the app or the widget reads the data: a session whose end has passed is
/// written to `focus_sessions`, with its end as `finished_at`, like the desktop does.
public struct FocusStore: Sendable {
    /// Same default as the desktop config (`focus_minutes`).
    public static let minutes = 25
    static let activeKey = "focus_active"

    private let database: DatabaseQueue

    public init(database: DatabaseQueue) {
        self.database = database
    }

    public func active() throws -> ActiveFocus? {
        try database.read { try Self.readActive($0) }
    }

    /// Starts a session. A session already running is kept and returned.
    @discardableResult
    public func start(
        minutes: Int = FocusStore.minutes,
        now: Date = .now,
        calendar: Calendar = .current
    ) throws -> ActiveFocus {
        try immediate { db in
            _ = try Self.settle(db, now: now, calendar: calendar)
            if let running = try Self.readActive(db) {
                return running
            }
            let range = FocusTimer.interval(startingAt: now, minutes: minutes)
            let session = ActiveFocus(
                start: range.lowerBound,
                end: range.upperBound,
                minutes: Int(range.upperBound.timeIntervalSince(range.lowerBound) / 60)
            )
            try Self.writeActive(session, db)
            return session
        }
    }

    /// Stops the running session without saving it.
    public func cancel() throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM settings WHERE key = ?", arguments: [Self.activeKey])
        }
    }

    /// Saves the running session if it has ended. Returns it when it was saved.
    @discardableResult
    public func settle(now: Date = .now, calendar: Calendar = .current) throws -> ActiveFocus? {
        try immediate { try Self.settle($0, now: now, calendar: calendar) }
    }

    /// Focus sessions finished on the day of `date`.
    public func sessions(on date: Date = .now, calendar: Calendar = .current) throws -> Int {
        try database.read { db in
            try Self.sessions(db, day: LocalTime.day(date, calendar: calendar))
        }
    }

    static func sessions(_ db: Database, day: String) throws -> Int {
        try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM focus_sessions WHERE date(finished_at) = ?",
            arguments: [day]
        ) ?? 0
    }

    static func settle(_ db: Database, now: Date, calendar: Calendar) throws -> ActiveFocus? {
        guard let session = try readActive(db), session.end <= now else {
            return nil
        }
        try db.execute(
            sql: "INSERT INTO focus_sessions (finished_at, minutes) VALUES (?, ?)",
            arguments: [LocalTime.timestamp(session.end, calendar: calendar), session.minutes]
        )
        try db.execute(sql: "DELETE FROM settings WHERE key = ?", arguments: [activeKey])
        return session
    }

    static func readActive(_ db: Database) throws -> ActiveFocus? {
        guard let text = try String.fetchOne(db, sql: "SELECT value FROM settings WHERE key = ?", arguments: [activeKey]) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(ActiveFocus.self, from: Data(text.utf8))
    }

    private static func writeActive(_ session: ActiveFocus, _ db: Database) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let text = String(decoding: try encoder.encode(session), as: UTF8.self)
        try db.execute(
            sql: """
            INSERT INTO settings (key, value) VALUES (?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value
            """,
            arguments: [activeKey, text]
        )
    }

    /// The app and the widget may settle at the same moment: the write lock is taken
    /// before reading, so a finished session is saved only once.
    private func immediate<T>(_ work: (Database) throws -> T) throws -> T {
        try database.writeWithoutTransaction { db in
            var result: T?
            try db.inTransaction(.immediate) {
                result = try work(db)
                return .commit
            }
            return result!
        }
    }
}
