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
        // v6: sync with the cloud (isleto-cloud; same migration in the desktop). Only adds:
        //   uuid (rows with an id), updated_at (UTC), updated_by (device) and dirty (not sent yet);
        //   sync_state: this device's id, the pull cursor, and the "applying" flag the sync engine
        //   sets while it writes remote rows (triggers then leave the rows alone);
        //   sync_tombstones: a copy of each deleted row, so the delete reaches the other devices.
        // Triggers keep those columns up to date, so app code keeps plain INSERT/UPDATE/DELETE.
        """
        CREATE TABLE sync_state (
            id        INTEGER PRIMARY KEY CHECK (id = 1),
            device_id TEXT NOT NULL,
            cursor    INTEGER NOT NULL DEFAULT 0,
            applying  INTEGER NOT NULL DEFAULT 0,
            last_sync TEXT NOT NULL DEFAULT ''
        );
        INSERT INTO sync_state (id, device_id) VALUES (1, lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' || substr(hex(randomblob(2)), 2) || '-' || substr('89ab', 1 + (abs(random()) % 4), 1) || substr(hex(randomblob(2)), 2) || '-' || hex(randomblob(6))));
        CREATE TABLE sync_tombstones (
            tbl        TEXT NOT NULL,
            key        TEXT NOT NULL,
            row        TEXT NOT NULL,
            deleted_at TEXT NOT NULL,
            deleted_by TEXT NOT NULL,
            PRIMARY KEY (tbl, key)
        );

        ALTER TABLE habits ADD COLUMN uuid TEXT;
        ALTER TABLE habit_categories ADD COLUMN uuid TEXT;
        ALTER TABLE water_logs ADD COLUMN uuid TEXT;
        ALTER TABLE focus_sessions ADD COLUMN uuid TEXT;
        ALTER TABLE habits ADD COLUMN updated_at TEXT NOT NULL DEFAULT '';
        ALTER TABLE habits ADD COLUMN updated_by TEXT NOT NULL DEFAULT '';
        ALTER TABLE habits ADD COLUMN dirty INTEGER NOT NULL DEFAULT 1;
        ALTER TABLE habit_checks ADD COLUMN updated_at TEXT NOT NULL DEFAULT '';
        ALTER TABLE habit_checks ADD COLUMN updated_by TEXT NOT NULL DEFAULT '';
        ALTER TABLE habit_checks ADD COLUMN dirty INTEGER NOT NULL DEFAULT 1;
        ALTER TABLE habit_categories ADD COLUMN updated_at TEXT NOT NULL DEFAULT '';
        ALTER TABLE habit_categories ADD COLUMN updated_by TEXT NOT NULL DEFAULT '';
        ALTER TABLE habit_categories ADD COLUMN dirty INTEGER NOT NULL DEFAULT 1;
        ALTER TABLE habit_category_links ADD COLUMN updated_at TEXT NOT NULL DEFAULT '';
        ALTER TABLE habit_category_links ADD COLUMN updated_by TEXT NOT NULL DEFAULT '';
        ALTER TABLE habit_category_links ADD COLUMN dirty INTEGER NOT NULL DEFAULT 1;
        ALTER TABLE water_logs ADD COLUMN updated_at TEXT NOT NULL DEFAULT '';
        ALTER TABLE water_logs ADD COLUMN updated_by TEXT NOT NULL DEFAULT '';
        ALTER TABLE water_logs ADD COLUMN dirty INTEGER NOT NULL DEFAULT 1;
        ALTER TABLE focus_sessions ADD COLUMN updated_at TEXT NOT NULL DEFAULT '';
        ALTER TABLE focus_sessions ADD COLUMN updated_by TEXT NOT NULL DEFAULT '';
        ALTER TABLE focus_sessions ADD COLUMN dirty INTEGER NOT NULL DEFAULT 1;

        UPDATE habits SET uuid = lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' || substr(hex(randomblob(2)), 2) || '-' || substr('89ab', 1 + (abs(random()) % 4), 1) || substr(hex(randomblob(2)), 2) || '-' || hex(randomblob(6)));
        UPDATE habit_categories SET uuid = lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' || substr(hex(randomblob(2)), 2) || '-' || substr('89ab', 1 + (abs(random()) % 4), 1) || substr(hex(randomblob(2)), 2) || '-' || hex(randomblob(6)));
        UPDATE water_logs SET uuid = lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' || substr(hex(randomblob(2)), 2) || '-' || substr('89ab', 1 + (abs(random()) % 4), 1) || substr(hex(randomblob(2)), 2) || '-' || hex(randomblob(6)));
        UPDATE focus_sessions SET uuid = lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' || substr(hex(randomblob(2)), 2) || '-' || substr('89ab', 1 + (abs(random()) % 4), 1) || substr(hex(randomblob(2)), 2) || '-' || hex(randomblob(6)));
        UPDATE habits SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), updated_by = (SELECT device_id FROM sync_state);
        UPDATE habit_checks SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), updated_by = (SELECT device_id FROM sync_state);
        UPDATE habit_categories SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), updated_by = (SELECT device_id FROM sync_state);
        UPDATE habit_category_links SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), updated_by = (SELECT device_id FROM sync_state);
        UPDATE water_logs SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), updated_by = (SELECT device_id FROM sync_state);
        UPDATE focus_sessions SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), updated_by = (SELECT device_id FROM sync_state);
        CREATE UNIQUE INDEX habits_uuid ON habits (uuid);
        CREATE UNIQUE INDEX habit_categories_uuid ON habit_categories (uuid);
        CREATE UNIQUE INDEX water_logs_uuid ON water_logs (uuid);
        CREATE UNIQUE INDEX focus_sessions_uuid ON focus_sessions (uuid);

        CREATE TRIGGER habits_sync_insert AFTER INSERT ON habits
        WHEN (SELECT applying FROM sync_state) = 0
        BEGIN
            UPDATE habits SET uuid = COALESCE(NEW.uuid, lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' || substr(hex(randomblob(2)), 2) || '-' || substr('89ab', 1 + (abs(random()) % 4), 1) || substr(hex(randomblob(2)), 2) || '-' || hex(randomblob(6)))),
                updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), updated_by = (SELECT device_id FROM sync_state), dirty = 1
            WHERE id = NEW.id;
            DELETE FROM sync_tombstones WHERE tbl = 'habits' AND key = (SELECT uuid FROM habits WHERE id = NEW.id);
        END;
        CREATE TRIGGER habits_sync_update AFTER UPDATE ON habits
        WHEN (SELECT applying FROM sync_state) = 0 AND NEW.updated_at IS OLD.updated_at AND NEW.dirty IS OLD.dirty
        BEGIN
            UPDATE habits SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), updated_by = (SELECT device_id FROM sync_state), dirty = 1
            WHERE id = NEW.id;
        END;
        CREATE TRIGGER habits_sync_delete AFTER DELETE ON habits
        WHEN (SELECT applying FROM sync_state) = 0 AND OLD.uuid IS NOT NULL
        BEGIN
            INSERT OR REPLACE INTO sync_tombstones (tbl, key, row, deleted_at, deleted_by) VALUES ('habits', OLD.uuid,
                json_object('id', OLD.uuid, 'name', OLD.name, 'created_at', OLD.created_at, 'description', OLD.description,
                    'icon', OLD.icon, 'color', OLD.color, 'kind', OLD.kind, 'schedule', OLD.schedule, 'record', OLD.record,
                    'target', OLD.target, 'unit', OLD.unit, 'reminders', OLD.reminders, 'archived', OLD.archived,
                    'sort_order', OLD.sort_order),
                strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), (SELECT device_id FROM sync_state));
        END;

        CREATE TRIGGER habit_checks_sync_insert AFTER INSERT ON habit_checks
        WHEN (SELECT applying FROM sync_state) = 0
        BEGIN
            UPDATE habit_checks SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), updated_by = (SELECT device_id FROM sync_state), dirty = 1
            WHERE habit_id = NEW.habit_id AND day = NEW.day;
            DELETE FROM sync_tombstones WHERE tbl = 'habit_checks'
                AND key = (SELECT uuid FROM habits WHERE id = NEW.habit_id) || '|' || NEW.day;
        END;
        CREATE TRIGGER habit_checks_sync_update AFTER UPDATE ON habit_checks
        WHEN (SELECT applying FROM sync_state) = 0 AND NEW.updated_at IS OLD.updated_at AND NEW.dirty IS OLD.dirty
        BEGIN
            UPDATE habit_checks SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), updated_by = (SELECT device_id FROM sync_state), dirty = 1
            WHERE habit_id = NEW.habit_id AND day = NEW.day;
        END;
        CREATE TRIGGER habit_checks_sync_delete AFTER DELETE ON habit_checks
        WHEN (SELECT applying FROM sync_state) = 0 AND (SELECT uuid FROM habits WHERE id = OLD.habit_id) IS NOT NULL
        BEGIN
            INSERT OR REPLACE INTO sync_tombstones (tbl, key, row, deleted_at, deleted_by) VALUES ('habit_checks',
                (SELECT uuid FROM habits WHERE id = OLD.habit_id) || '|' || OLD.day,
                json_object('habit_id', (SELECT uuid FROM habits WHERE id = OLD.habit_id), 'day', OLD.day, 'value', OLD.value),
                strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), (SELECT device_id FROM sync_state));
        END;

        CREATE TRIGGER habit_categories_sync_insert AFTER INSERT ON habit_categories
        WHEN (SELECT applying FROM sync_state) = 0
        BEGIN
            UPDATE habit_categories SET uuid = COALESCE(NEW.uuid, lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' || substr(hex(randomblob(2)), 2) || '-' || substr('89ab', 1 + (abs(random()) % 4), 1) || substr(hex(randomblob(2)), 2) || '-' || hex(randomblob(6)))),
                updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), updated_by = (SELECT device_id FROM sync_state), dirty = 1
            WHERE id = NEW.id;
            DELETE FROM sync_tombstones WHERE tbl = 'habit_categories' AND key = (SELECT uuid FROM habit_categories WHERE id = NEW.id);
        END;
        CREATE TRIGGER habit_categories_sync_update AFTER UPDATE ON habit_categories
        WHEN (SELECT applying FROM sync_state) = 0 AND NEW.updated_at IS OLD.updated_at AND NEW.dirty IS OLD.dirty
        BEGIN
            UPDATE habit_categories SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), updated_by = (SELECT device_id FROM sync_state), dirty = 1
            WHERE id = NEW.id;
        END;
        CREATE TRIGGER habit_categories_sync_delete AFTER DELETE ON habit_categories
        WHEN (SELECT applying FROM sync_state) = 0 AND OLD.uuid IS NOT NULL
        BEGIN
            INSERT OR REPLACE INTO sync_tombstones (tbl, key, row, deleted_at, deleted_by) VALUES ('habit_categories', OLD.uuid,
                json_object('id', OLD.uuid, 'name', OLD.name, 'created_at', OLD.created_at),
                strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), (SELECT device_id FROM sync_state));
        END;

        CREATE TRIGGER habit_category_links_sync_insert AFTER INSERT ON habit_category_links
        WHEN (SELECT applying FROM sync_state) = 0
        BEGIN
            UPDATE habit_category_links SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), updated_by = (SELECT device_id FROM sync_state), dirty = 1
            WHERE habit_id = NEW.habit_id AND category_id = NEW.category_id;
            DELETE FROM sync_tombstones WHERE tbl = 'habit_category_links'
                AND key = (SELECT uuid FROM habits WHERE id = NEW.habit_id) || '|' || (SELECT uuid FROM habit_categories WHERE id = NEW.category_id);
        END;
        CREATE TRIGGER habit_category_links_sync_update AFTER UPDATE ON habit_category_links
        WHEN (SELECT applying FROM sync_state) = 0 AND NEW.updated_at IS OLD.updated_at AND NEW.dirty IS OLD.dirty
        BEGIN
            UPDATE habit_category_links SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), updated_by = (SELECT device_id FROM sync_state), dirty = 1
            WHERE habit_id = NEW.habit_id AND category_id = NEW.category_id;
        END;
        CREATE TRIGGER habit_category_links_sync_delete AFTER DELETE ON habit_category_links
        WHEN (SELECT applying FROM sync_state) = 0
            AND (SELECT uuid FROM habits WHERE id = OLD.habit_id) IS NOT NULL
            AND (SELECT uuid FROM habit_categories WHERE id = OLD.category_id) IS NOT NULL
        BEGIN
            INSERT OR REPLACE INTO sync_tombstones (tbl, key, row, deleted_at, deleted_by) VALUES ('habit_category_links',
                (SELECT uuid FROM habits WHERE id = OLD.habit_id) || '|' || (SELECT uuid FROM habit_categories WHERE id = OLD.category_id),
                json_object('habit_id', (SELECT uuid FROM habits WHERE id = OLD.habit_id),
                    'category_id', (SELECT uuid FROM habit_categories WHERE id = OLD.category_id)),
                strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), (SELECT device_id FROM sync_state));
        END;

        CREATE TRIGGER water_logs_sync_insert AFTER INSERT ON water_logs
        WHEN (SELECT applying FROM sync_state) = 0
        BEGIN
            UPDATE water_logs SET uuid = COALESCE(NEW.uuid, lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' || substr(hex(randomblob(2)), 2) || '-' || substr('89ab', 1 + (abs(random()) % 4), 1) || substr(hex(randomblob(2)), 2) || '-' || hex(randomblob(6)))),
                updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), updated_by = (SELECT device_id FROM sync_state), dirty = 1
            WHERE id = NEW.id;
        END;
        CREATE TRIGGER water_logs_sync_update AFTER UPDATE ON water_logs
        WHEN (SELECT applying FROM sync_state) = 0 AND NEW.updated_at IS OLD.updated_at AND NEW.dirty IS OLD.dirty
        BEGIN
            UPDATE water_logs SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), updated_by = (SELECT device_id FROM sync_state), dirty = 1
            WHERE id = NEW.id;
        END;
        CREATE TRIGGER water_logs_sync_delete AFTER DELETE ON water_logs
        WHEN (SELECT applying FROM sync_state) = 0 AND OLD.uuid IS NOT NULL
        BEGIN
            INSERT OR REPLACE INTO sync_tombstones (tbl, key, row, deleted_at, deleted_by) VALUES ('water_logs', OLD.uuid,
                json_object('id', OLD.uuid, 'logged_at', OLD.logged_at, 'ml', OLD.ml),
                strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), (SELECT device_id FROM sync_state));
        END;

        CREATE TRIGGER focus_sessions_sync_insert AFTER INSERT ON focus_sessions
        WHEN (SELECT applying FROM sync_state) = 0
        BEGIN
            UPDATE focus_sessions SET uuid = COALESCE(NEW.uuid, lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' || substr(hex(randomblob(2)), 2) || '-' || substr('89ab', 1 + (abs(random()) % 4), 1) || substr(hex(randomblob(2)), 2) || '-' || hex(randomblob(6)))),
                updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), updated_by = (SELECT device_id FROM sync_state), dirty = 1
            WHERE id = NEW.id;
        END;
        CREATE TRIGGER focus_sessions_sync_update AFTER UPDATE ON focus_sessions
        WHEN (SELECT applying FROM sync_state) = 0 AND NEW.updated_at IS OLD.updated_at AND NEW.dirty IS OLD.dirty
        BEGIN
            UPDATE focus_sessions SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), updated_by = (SELECT device_id FROM sync_state), dirty = 1
            WHERE id = NEW.id;
        END;
        CREATE TRIGGER focus_sessions_sync_delete AFTER DELETE ON focus_sessions
        WHEN (SELECT applying FROM sync_state) = 0 AND OLD.uuid IS NOT NULL
        BEGIN
            INSERT OR REPLACE INTO sync_tombstones (tbl, key, row, deleted_at, deleted_by) VALUES ('focus_sessions', OLD.uuid,
                json_object('id', OLD.uuid, 'finished_at', OLD.finished_at, 'minutes', OLD.minutes),
                strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), (SELECT device_id FROM sync_state));
        END;
        """,
        // v7: workouts (same migration in the desktop and the isleto-cloud tables). Only adds tables:
        //   exercises: the exercise library (catalog exercises get a fixed uuid, so two devices
        //   adding the same one write the same row); workout_plans ("fichas") and their exercises;
        //   workouts: one per session, finished_at = '' while it runs; workout_sets: the sets
        //   of a workout (weight in kg). Same sync columns and triggers as v6. A child's tombstone
        //   may have a null parent uuid when the parent was deleted first (cascade).
        """
        CREATE TABLE exercises (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            name        TEXT NOT NULL,
            muscle      TEXT NOT NULL DEFAULT '',
            notes       TEXT NOT NULL DEFAULT '',
            archived    INTEGER NOT NULL DEFAULT 0,
            created_at  TEXT NOT NULL DEFAULT (datetime('now', 'localtime')),
            uuid        TEXT,
            updated_at  TEXT NOT NULL DEFAULT '',
            updated_by  TEXT NOT NULL DEFAULT '',
            dirty       INTEGER NOT NULL DEFAULT 1
        );
        CREATE UNIQUE INDEX exercises_uuid ON exercises (uuid);
        CREATE TABLE workout_plans (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            name        TEXT NOT NULL,
            notes       TEXT NOT NULL DEFAULT '',
            sort_order  INTEGER NOT NULL DEFAULT 0,
            archived    INTEGER NOT NULL DEFAULT 0,
            created_at  TEXT NOT NULL DEFAULT (datetime('now', 'localtime')),
            uuid        TEXT,
            updated_at  TEXT NOT NULL DEFAULT '',
            updated_by  TEXT NOT NULL DEFAULT '',
            dirty       INTEGER NOT NULL DEFAULT 1
        );
        CREATE UNIQUE INDEX workout_plans_uuid ON workout_plans (uuid);
        CREATE TABLE workout_plan_exercises (
            id           INTEGER PRIMARY KEY AUTOINCREMENT,
            plan_id      INTEGER NOT NULL REFERENCES workout_plans(id) ON DELETE CASCADE,
            exercise_id  INTEGER NOT NULL REFERENCES exercises(id) ON DELETE CASCADE,
            position     INTEGER NOT NULL DEFAULT 0,
            sets         INTEGER NOT NULL DEFAULT 3,
            reps         TEXT NOT NULL DEFAULT '10',
            rest_seconds INTEGER NOT NULL DEFAULT 90,
            uuid        TEXT,
            updated_at  TEXT NOT NULL DEFAULT '',
            updated_by  TEXT NOT NULL DEFAULT '',
            dirty       INTEGER NOT NULL DEFAULT 1
        );
        CREATE UNIQUE INDEX workout_plan_exercises_uuid ON workout_plan_exercises (uuid);
        CREATE TABLE workouts (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            plan_id     INTEGER REFERENCES workout_plans(id) ON DELETE SET NULL,
            name        TEXT NOT NULL,
            started_at  TEXT NOT NULL DEFAULT (datetime('now', 'localtime')),
            finished_at TEXT NOT NULL DEFAULT '',
            notes       TEXT NOT NULL DEFAULT '',
            uuid        TEXT,
            updated_at  TEXT NOT NULL DEFAULT '',
            updated_by  TEXT NOT NULL DEFAULT '',
            dirty       INTEGER NOT NULL DEFAULT 1
        );
        CREATE UNIQUE INDEX workouts_uuid ON workouts (uuid);
        CREATE TABLE workout_sets (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            workout_id  INTEGER NOT NULL REFERENCES workouts(id) ON DELETE CASCADE,
            exercise_id INTEGER NOT NULL REFERENCES exercises(id) ON DELETE CASCADE,
            position    INTEGER NOT NULL DEFAULT 0,
            set_number  INTEGER NOT NULL DEFAULT 1,
            reps        INTEGER NOT NULL DEFAULT 0,
            weight      REAL NOT NULL DEFAULT 0,
            done        INTEGER NOT NULL DEFAULT 0,
            done_at     TEXT NOT NULL DEFAULT '',
            uuid        TEXT,
            updated_at  TEXT NOT NULL DEFAULT '',
            updated_by  TEXT NOT NULL DEFAULT '',
            dirty       INTEGER NOT NULL DEFAULT 1
        );
        CREATE UNIQUE INDEX workout_sets_uuid ON workout_sets (uuid);
        CREATE INDEX workout_plan_exercises_plan ON workout_plan_exercises (plan_id);
        CREATE INDEX workouts_started ON workouts (started_at);
        CREATE INDEX workout_sets_workout ON workout_sets (workout_id);
        CREATE INDEX workout_sets_exercise ON workout_sets (exercise_id);
        CREATE TRIGGER exercises_sync_insert AFTER INSERT ON exercises
        WHEN (SELECT applying FROM sync_state) = 0
        BEGIN
            UPDATE exercises SET uuid = COALESCE(NEW.uuid, lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' || substr(hex(randomblob(2)), 2) || '-' || substr('89ab', 1 + (abs(random()) % 4), 1) || substr(hex(randomblob(2)), 2) || '-' || hex(randomblob(6)))),
                updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), updated_by = (SELECT device_id FROM sync_state), dirty = 1
            WHERE id = NEW.id;
            DELETE FROM sync_tombstones WHERE tbl = 'exercises' AND key = (SELECT uuid FROM exercises WHERE id = NEW.id);
        END;
        CREATE TRIGGER exercises_sync_update AFTER UPDATE ON exercises
        WHEN (SELECT applying FROM sync_state) = 0 AND NEW.updated_at IS OLD.updated_at AND NEW.dirty IS OLD.dirty
        BEGIN
            UPDATE exercises SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), updated_by = (SELECT device_id FROM sync_state), dirty = 1
            WHERE id = NEW.id;
        END;
        CREATE TRIGGER exercises_sync_delete AFTER DELETE ON exercises
        WHEN (SELECT applying FROM sync_state) = 0 AND OLD.uuid IS NOT NULL
        BEGIN
            INSERT OR REPLACE INTO sync_tombstones (tbl, key, row, deleted_at, deleted_by) VALUES ('exercises', OLD.uuid,
                json_object('id', OLD.uuid, 'name', OLD.name, 'muscle', OLD.muscle, 'notes', OLD.notes,
                'archived', OLD.archived, 'created_at', OLD.created_at),
                strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), (SELECT device_id FROM sync_state));
        END;
        CREATE TRIGGER workout_plans_sync_insert AFTER INSERT ON workout_plans
        WHEN (SELECT applying FROM sync_state) = 0
        BEGIN
            UPDATE workout_plans SET uuid = COALESCE(NEW.uuid, lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' || substr(hex(randomblob(2)), 2) || '-' || substr('89ab', 1 + (abs(random()) % 4), 1) || substr(hex(randomblob(2)), 2) || '-' || hex(randomblob(6)))),
                updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), updated_by = (SELECT device_id FROM sync_state), dirty = 1
            WHERE id = NEW.id;
            DELETE FROM sync_tombstones WHERE tbl = 'workout_plans' AND key = (SELECT uuid FROM workout_plans WHERE id = NEW.id);
        END;
        CREATE TRIGGER workout_plans_sync_update AFTER UPDATE ON workout_plans
        WHEN (SELECT applying FROM sync_state) = 0 AND NEW.updated_at IS OLD.updated_at AND NEW.dirty IS OLD.dirty
        BEGIN
            UPDATE workout_plans SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), updated_by = (SELECT device_id FROM sync_state), dirty = 1
            WHERE id = NEW.id;
        END;
        CREATE TRIGGER workout_plans_sync_delete AFTER DELETE ON workout_plans
        WHEN (SELECT applying FROM sync_state) = 0 AND OLD.uuid IS NOT NULL
        BEGIN
            INSERT OR REPLACE INTO sync_tombstones (tbl, key, row, deleted_at, deleted_by) VALUES ('workout_plans', OLD.uuid,
                json_object('id', OLD.uuid, 'name', OLD.name, 'notes', OLD.notes, 'sort_order', OLD.sort_order,
                'archived', OLD.archived, 'created_at', OLD.created_at),
                strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), (SELECT device_id FROM sync_state));
        END;
        CREATE TRIGGER workout_plan_exercises_sync_insert AFTER INSERT ON workout_plan_exercises
        WHEN (SELECT applying FROM sync_state) = 0
        BEGIN
            UPDATE workout_plan_exercises SET uuid = COALESCE(NEW.uuid, lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' || substr(hex(randomblob(2)), 2) || '-' || substr('89ab', 1 + (abs(random()) % 4), 1) || substr(hex(randomblob(2)), 2) || '-' || hex(randomblob(6)))),
                updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), updated_by = (SELECT device_id FROM sync_state), dirty = 1
            WHERE id = NEW.id;
            DELETE FROM sync_tombstones WHERE tbl = 'workout_plan_exercises' AND key = (SELECT uuid FROM workout_plan_exercises WHERE id = NEW.id);
        END;
        CREATE TRIGGER workout_plan_exercises_sync_update AFTER UPDATE ON workout_plan_exercises
        WHEN (SELECT applying FROM sync_state) = 0 AND NEW.updated_at IS OLD.updated_at AND NEW.dirty IS OLD.dirty
        BEGIN
            UPDATE workout_plan_exercises SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), updated_by = (SELECT device_id FROM sync_state), dirty = 1
            WHERE id = NEW.id;
        END;
        CREATE TRIGGER workout_plan_exercises_sync_delete AFTER DELETE ON workout_plan_exercises
        WHEN (SELECT applying FROM sync_state) = 0 AND OLD.uuid IS NOT NULL
        BEGIN
            INSERT OR REPLACE INTO sync_tombstones (tbl, key, row, deleted_at, deleted_by) VALUES ('workout_plan_exercises', OLD.uuid,
                json_object('id', OLD.uuid, 'plan_id', (SELECT uuid FROM workout_plans WHERE id = OLD.plan_id),
                'exercise_id', (SELECT uuid FROM exercises WHERE id = OLD.exercise_id),
                'position', OLD.position, 'sets', OLD.sets, 'reps', OLD.reps,
                'rest_seconds', OLD.rest_seconds),
                strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), (SELECT device_id FROM sync_state));
        END;
        CREATE TRIGGER workouts_sync_insert AFTER INSERT ON workouts
        WHEN (SELECT applying FROM sync_state) = 0
        BEGIN
            UPDATE workouts SET uuid = COALESCE(NEW.uuid, lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' || substr(hex(randomblob(2)), 2) || '-' || substr('89ab', 1 + (abs(random()) % 4), 1) || substr(hex(randomblob(2)), 2) || '-' || hex(randomblob(6)))),
                updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), updated_by = (SELECT device_id FROM sync_state), dirty = 1
            WHERE id = NEW.id;
            DELETE FROM sync_tombstones WHERE tbl = 'workouts' AND key = (SELECT uuid FROM workouts WHERE id = NEW.id);
        END;
        CREATE TRIGGER workouts_sync_update AFTER UPDATE ON workouts
        WHEN (SELECT applying FROM sync_state) = 0 AND NEW.updated_at IS OLD.updated_at AND NEW.dirty IS OLD.dirty
        BEGIN
            UPDATE workouts SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), updated_by = (SELECT device_id FROM sync_state), dirty = 1
            WHERE id = NEW.id;
        END;
        CREATE TRIGGER workouts_sync_delete AFTER DELETE ON workouts
        WHEN (SELECT applying FROM sync_state) = 0 AND OLD.uuid IS NOT NULL
        BEGIN
            INSERT OR REPLACE INTO sync_tombstones (tbl, key, row, deleted_at, deleted_by) VALUES ('workouts', OLD.uuid,
                json_object('id', OLD.uuid, 'plan_id', (SELECT uuid FROM workout_plans WHERE id = OLD.plan_id),
                'name', OLD.name, 'started_at', OLD.started_at, 'finished_at', OLD.finished_at,
                'notes', OLD.notes),
                strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), (SELECT device_id FROM sync_state));
        END;
        CREATE TRIGGER workout_sets_sync_insert AFTER INSERT ON workout_sets
        WHEN (SELECT applying FROM sync_state) = 0
        BEGIN
            UPDATE workout_sets SET uuid = COALESCE(NEW.uuid, lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' || substr(hex(randomblob(2)), 2) || '-' || substr('89ab', 1 + (abs(random()) % 4), 1) || substr(hex(randomblob(2)), 2) || '-' || hex(randomblob(6)))),
                updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), updated_by = (SELECT device_id FROM sync_state), dirty = 1
            WHERE id = NEW.id;
            DELETE FROM sync_tombstones WHERE tbl = 'workout_sets' AND key = (SELECT uuid FROM workout_sets WHERE id = NEW.id);
        END;
        CREATE TRIGGER workout_sets_sync_update AFTER UPDATE ON workout_sets
        WHEN (SELECT applying FROM sync_state) = 0 AND NEW.updated_at IS OLD.updated_at AND NEW.dirty IS OLD.dirty
        BEGIN
            UPDATE workout_sets SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), updated_by = (SELECT device_id FROM sync_state), dirty = 1
            WHERE id = NEW.id;
        END;
        CREATE TRIGGER workout_sets_sync_delete AFTER DELETE ON workout_sets
        WHEN (SELECT applying FROM sync_state) = 0 AND OLD.uuid IS NOT NULL
        BEGIN
            INSERT OR REPLACE INTO sync_tombstones (tbl, key, row, deleted_at, deleted_by) VALUES ('workout_sets', OLD.uuid,
                json_object('id', OLD.uuid, 'workout_id', (SELECT uuid FROM workouts WHERE id = OLD.workout_id),
                'exercise_id', (SELECT uuid FROM exercises WHERE id = OLD.exercise_id),
                'position', OLD.position, 'set_number', OLD.set_number, 'reps', OLD.reps,
                'weight', OLD.weight, 'done', OLD.done, 'done_at', OLD.done_at),
                strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), (SELECT device_id FROM sync_state));
        END;
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
