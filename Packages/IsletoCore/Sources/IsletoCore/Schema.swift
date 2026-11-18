import GRDB

/// The database schema, identical to the desktop app (`isleto/src/db.rs`).
///
/// Same SQL, same mechanism: migration index + 1 is stored in `PRAGMA user_version`.
/// Append-only. Never edit a migration that already shipped: add a new one, here AND
/// on the desktop, so a database file can move between the two apps unchanged.
public enum Schema {
    public static let migrations: [String] = [
        // v1: generic key/value store for app state.
        """
        CREATE TABLE settings (
            key   TEXT PRIMARY KEY NOT NULL,
            value TEXT NOT NULL
        );
        """,
        // v2: finished focus (pomodoro) sessions.
        """
        CREATE TABLE focus_sessions (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            finished_at TEXT NOT NULL DEFAULT (datetime('now', 'localtime')),
            minutes     INTEGER NOT NULL
        );
        """,
        // v3: water drunk.
        """
        CREATE TABLE water_logs (
            id        INTEGER PRIMARY KEY AUTOINCREMENT,
            logged_at TEXT NOT NULL DEFAULT (datetime('now', 'localtime')),
            ml        INTEGER NOT NULL
        );
        """,
        // v4: daily habits and the days each one was done.
        """
        CREATE TABLE habits (
            id         INTEGER PRIMARY KEY AUTOINCREMENT,
            name       TEXT NOT NULL,
            created_at TEXT NOT NULL DEFAULT (datetime('now', 'localtime'))
        );
        CREATE TABLE habit_checks (
            habit_id INTEGER NOT NULL REFERENCES habits(id) ON DELETE CASCADE,
            day      TEXT NOT NULL,
            PRIMARY KEY (habit_id, day)
        );
        """,
        // v5: richer habits (same migration in the desktop). Only adds columns and tables.
        //   kind: 'build' | 'quit' (a quit habit's check marks a relapse)
        //   schedule: 'daily' | 'weekdays:1,3,5' (1 = Monday) | 'weekly:3' (times per week)
        //   record: 'check' | 'count' | 'measure'; habit_checks.value holds the count or measure
        //   reminders: 'HH:MM' times separated by commas; color: '#RRGGBB'
        """
        ALTER TABLE habits ADD COLUMN description TEXT NOT NULL DEFAULT '';
        ALTER TABLE habits ADD COLUMN icon TEXT NOT NULL DEFAULT 'checkmark';
        ALTER TABLE habits ADD COLUMN color TEXT NOT NULL DEFAULT '#3AA76D';
        ALTER TABLE habits ADD COLUMN kind TEXT NOT NULL DEFAULT 'build';
        ALTER TABLE habits ADD COLUMN schedule TEXT NOT NULL DEFAULT 'daily';
        ALTER TABLE habits ADD COLUMN record TEXT NOT NULL DEFAULT 'check';
        ALTER TABLE habits ADD COLUMN target REAL NOT NULL DEFAULT 1;
        ALTER TABLE habits ADD COLUMN unit TEXT NOT NULL DEFAULT '';
        ALTER TABLE habits ADD COLUMN reminders TEXT NOT NULL DEFAULT '';
        ALTER TABLE habits ADD COLUMN archived INTEGER NOT NULL DEFAULT 0;
        ALTER TABLE habits ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0;
        ALTER TABLE habit_checks ADD COLUMN value REAL NOT NULL DEFAULT 1;
        CREATE TABLE habit_categories (
            id         INTEGER PRIMARY KEY AUTOINCREMENT,
            name       TEXT NOT NULL UNIQUE,
            created_at TEXT NOT NULL DEFAULT (datetime('now', 'localtime'))
        );
        CREATE TABLE habit_category_links (
            habit_id    INTEGER NOT NULL REFERENCES habits(id) ON DELETE CASCADE,
            category_id INTEGER NOT NULL REFERENCES habit_categories(id) ON DELETE CASCADE,
            PRIMARY KEY (habit_id, category_id)
        );
        """,
    ]

    /// Current schema version of the database.
    public static func version(_ db: Database) throws -> Int {
        try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0
    }

    /// Applies pending migrations, one transaction per migration, like the desktop.
    ///
    /// The app and the widget extension are separate processes that may open the
    /// database at the same moment. The version is read inside an IMMEDIATE
    /// transaction (write lock taken first), so two processes never run the same
    /// migration twice. Must be called outside a transaction.
    public static func migrate(_ db: Database) throws {
        while true {
            var finished = false
            try db.inTransaction(.immediate) {
                let current = try version(db)
                guard current < migrations.count else {
                    finished = true
                    return .commit
                }
                try db.execute(sql: migrations[current])
                try db.execute(sql: "PRAGMA user_version = \(current + 1)")
                return .commit
            }
            if finished { return }
        }
    }
}
