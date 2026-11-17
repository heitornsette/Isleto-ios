import Foundation
import GRDB

/// Opens the shared SQLite database.
public enum IsletoDatabase {
    /// Same file name as the desktop (`%APPDATA%\Isleto\isleto.db`).
    public static let fileName = "isleto.db"

    /// Opens (creating if needed) the database file and applies pending migrations.
    public static func open(at url: URL) throws -> DatabaseQueue {
        let queue = try DatabaseQueue(path: url.path(percentEncoded: false), configuration: configuration())
        try queue.writeWithoutTransaction { try Schema.migrate($0) }
        return queue
    }

    /// In-memory database with the full schema, for tests.
    public static func inMemory() throws -> DatabaseQueue {
        let queue = try DatabaseQueue(configuration: configuration())
        try queue.writeWithoutTransaction { try Schema.migrate($0) }
        return queue
    }

    private static func configuration() -> Configuration {
        var config = Configuration()
        // The app and the widget extension write to the same file from two processes.
        // Wait for the other one's lock instead of failing at once with SQLITE_BUSY.
        config.busyMode = .timeout(5)
        return config
    }
}
