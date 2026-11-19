import Foundation
import GRDB

/// Workouts (migration v7): the exercise library, plans ("fichas"), workout sessions and
/// their sets. Plain INSERT/UPDATE/DELETE: the sync triggers mark every change.
public struct WorkoutStore: Sendable {
    /// Rest after a set when the plan does not say.
    public static let defaultRestSeconds = 90
    public static let maximumNameLength = 40

    private let database: DatabaseQueue

    public init(database: DatabaseQueue) {
        self.database = database
    }

    static func cleanName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(maximumNameLength))
    }

    // MARK: Exercises

    public func exercises(includeArchived: Bool = false) throws -> [Exercise] {
        try database.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, uuid, name, muscle, notes, archived FROM exercises
                \(includeArchived ? "" : "WHERE archived = 0")
                ORDER BY name COLLATE NOCASE, id
                """).map(Self.exercise)
        }
    }

    public func exercise(id: Int64) throws -> Exercise? {
        try database.read { db in
            try Row.fetchOne(
                db, sql: "SELECT id, uuid, name, muscle, notes, archived FROM exercises WHERE id = ?", arguments: [id]
            ).map(Self.exercise)
        }
    }

    private static func exercise(_ row: Row) -> Exercise {
        Exercise(
            id: row["id"],
            uuid: row["uuid"] ?? "",
            name: row["name"],
            muscle: Muscle(storage: row["muscle"]),
            notes: row["notes"],
            archived: (row["archived"] as Int) != 0
        )
    }

    /// Catalog exercises not in the library yet (an archived one counts as in it).
    public func catalogNotInLibrary() throws -> [CatalogExercise] {
        let used = try database.read { Set(try String.fetchAll($0, sql: "SELECT uuid FROM exercises WHERE uuid IS NOT NULL")) }
        return ExerciseCatalog.all.filter { !used.contains($0.uuid) }
    }

    /// The library id of a catalog exercise: added with its fixed uuid the first time,
    /// brought back if it was archived.
    @discardableResult
    public func exerciseID(for entry: CatalogExercise) throws -> Int64 {
        try database.write { db in
            if let row = try Row.fetchOne(db, sql: "SELECT id, archived FROM exercises WHERE uuid = ?", arguments: [entry.uuid]) {
                let id: Int64 = row["id"]
                if (row["archived"] as Int) != 0 {
                    try db.execute(sql: "UPDATE exercises SET archived = 0 WHERE id = ?", arguments: [id])
                }
                return id
            }
            try db.execute(
                sql: "INSERT INTO exercises (uuid, name, muscle) VALUES (?, ?, ?)",
                arguments: [entry.uuid, entry.name, entry.muscle.rawValue]
            )
            return db.lastInsertedRowID
        }
    }

    /// A new exercise of the user's own. Nil if the name is empty.
    @discardableResult
    public func createExercise(name: String, muscle: Muscle) throws -> Int64? {
        guard let name = Self.cleanName(name) else { return nil }
        return try database.write { db in
            try db.execute(sql: "INSERT INTO exercises (name, muscle) VALUES (?, ?)", arguments: [name, muscle.rawValue])
            return db.lastInsertedRowID
        }
    }

    public func updateExercise(id: Int64, name: String, muscle: Muscle, notes: String) throws {
        guard let name = Self.cleanName(name) else { return }
        try database.write { db in
            try db.execute(
                sql: "UPDATE exercises SET name = ?, muscle = ?, notes = ? WHERE id = ?",
                arguments: [name, muscle.rawValue, notes, id]
            )
        }
    }

    /// Deletes an exercise never used in a workout; archives one with history, so the
    /// history stays. True if it was deleted.
    @discardableResult
    public func removeExercise(id: Int64) throws -> Bool {
        try database.write { db in
            let used = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM workout_sets WHERE exercise_id = ?", arguments: [id]) ?? 0
            if used > 0 {
                try db.execute(sql: "UPDATE exercises SET archived = 1 WHERE id = ?", arguments: [id])
                try db.execute(sql: "DELETE FROM workout_plan_exercises WHERE exercise_id = ?", arguments: [id])
                return false
            }
            try db.execute(sql: "DELETE FROM workout_plan_exercises WHERE exercise_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM exercises WHERE id = ?", arguments: [id])
            return true
        }
    }

    // MARK: Plans

    public func plans() throws -> [WorkoutPlan] {
        try database.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT id, name, notes, sort_order FROM workout_plans WHERE archived = 0 ORDER BY sort_order, id
                """)
            let exercises = try Self.planExercises(db, planID: nil)
            return rows.map { row in
                let id: Int64 = row["id"]
                return WorkoutPlan(
                    id: id, name: row["name"], notes: row["notes"], sortOrder: row["sort_order"],
                    exercises: exercises[id] ?? []
                )
            }
        }
    }

    public func plan(id: Int64) throws -> WorkoutPlan? {
        try plans().first { $0.id == id }
    }

    private static func planExercises(_ db: Database, planID: Int64?) throws -> [Int64: [PlanExercise]] {
        var result: [Int64: [PlanExercise]] = [:]
        let rows = try Row.fetchAll(db, sql: """
            SELECT x.id, x.plan_id, x.exercise_id, x.position, x.sets, x.reps, x.rest_seconds, e.name, e.muscle
            FROM workout_plan_exercises x JOIN exercises e ON e.id = x.exercise_id
            \(planID.map { "WHERE x.plan_id = \($0)" } ?? "")
            ORDER BY x.position, x.id
            """)
        for row in rows {
            result[row["plan_id"], default: []].append(PlanExercise(
                id: row["id"], exerciseID: row["exercise_id"], name: row["name"], muscle: Muscle(storage: row["muscle"]),
                position: row["position"], sets: row["sets"], reps: row["reps"], restSeconds: row["rest_seconds"]
            ))
        }
        return result
    }

    /// A new plan at the end of the list. Nil if the name is empty.
    @discardableResult
    public func createPlan(name: String) throws -> Int64? {
        guard let name = Self.cleanName(name) else { return nil }
        return try database.write { db in
            let order = try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(sort_order), -1) + 1 FROM workout_plans") ?? 0
            try db.execute(sql: "INSERT INTO workout_plans (name, sort_order) VALUES (?, ?)", arguments: [name, order])
            return db.lastInsertedRowID
        }
    }

    public func renamePlan(id: Int64, name: String) throws {
        guard let name = Self.cleanName(name) else { return }
        try database.write { db in
            try db.execute(sql: "UPDATE workout_plans SET name = ? WHERE id = ?", arguments: [name, id])
        }
    }

    /// Deletes the plan and its exercise list. Past workouts stay, without a plan.
    public func deletePlan(id: Int64) throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM workout_plan_exercises WHERE plan_id = ?", arguments: [id])
            try db.execute(sql: "UPDATE workouts SET plan_id = NULL WHERE plan_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM workout_plans WHERE id = ?", arguments: [id])
        }
    }

    @discardableResult
    public func addExercise(_ exerciseID: Int64, toPlan planID: Int64) throws -> Int64 {
        try database.write { db in
            let position = try Int.fetchOne(
                db, sql: "SELECT COALESCE(MAX(position), -1) + 1 FROM workout_plan_exercises WHERE plan_id = ?", arguments: [planID]
            ) ?? 0
            try db.execute(
                sql: "INSERT INTO workout_plan_exercises (plan_id, exercise_id, position, rest_seconds) VALUES (?, ?, ?, ?)",
                arguments: [planID, exerciseID, position, Self.defaultRestSeconds]
            )
            return db.lastInsertedRowID
        }
    }

    public func updatePlanExercise(id: Int64, sets: Int, reps: String, restSeconds: Int) throws {
        let reps = reps.trimmingCharacters(in: .whitespaces)
        try database.write { db in
            try db.execute(
                sql: "UPDATE workout_plan_exercises SET sets = ?, reps = ?, rest_seconds = ? WHERE id = ?",
                arguments: [min(max(sets, 1), 20), reps.isEmpty ? "10" : String(reps.prefix(12)), min(max(restSeconds, 0), 600), id]
            )
        }
    }

    public func removePlanExercise(id: Int64) throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM workout_plan_exercises WHERE id = ?", arguments: [id])
        }
    }

    /// Saves a new order: `ids` are the plan's exercise rows, first to last.
    public func reorderPlan(_ planID: Int64, ids: [Int64]) throws {
        try database.write { db in
            for (position, id) in ids.enumerated() {
                try db.execute(
                    sql: "UPDATE workout_plan_exercises SET position = ? WHERE id = ? AND plan_id = ? AND position != ?",
                    arguments: [position, id, planID, position]
                )
            }
        }
    }

    // MARK: Workouts

    /// The running workout, if any (the newest one, if two devices left one open).
    public func activeWorkout() throws -> Workout? {
        try database.read { db in
            guard let id = try Int64.fetchOne(
                db, sql: "SELECT id FROM workouts WHERE finished_at = '' ORDER BY started_at DESC, id DESC LIMIT 1"
            ) else { return nil }
            return try Self.workout(db, id: id)
        }
    }

    public func workout(id: Int64) throws -> Workout? {
        try database.read { try Self.workout($0, id: id) }
    }

    /// Starts a workout, from a plan or empty. The plan's sets come filled with what was
    /// done last time (or the plan's reps and no weight). A running workout is kept and
    /// returned instead.
    @discardableResult
    public func startWorkout(planID: Int64?, now: Date = .now, calendar: Calendar = .current) throws -> Int64 {
        try database.write { db in
            if let running = try Int64.fetchOne(db, sql: "SELECT id FROM workouts WHERE finished_at = '' ORDER BY started_at DESC LIMIT 1") {
                return running
            }
            let plan = try planID.flatMap { try Row.fetchOne(db, sql: "SELECT id, name FROM workout_plans WHERE id = ?", arguments: [$0]) }
            let planRowID: Int64? = plan.map { $0["id"] }
            let name: String = plan.map { $0["name"] } ?? "Treino livre"
            try db.execute(
                sql: "INSERT INTO workouts (plan_id, name, started_at) VALUES (?, ?, ?)",
                arguments: [planRowID, name, LocalTime.timestamp(now, calendar: calendar)]
            )
            let workoutID = db.lastInsertedRowID
            if let planID = planRowID {
                for exercise in try Self.planExercises(db, planID: planID)[planID] ?? [] {
                    try Self.appendSets(
                        db, workoutID: workoutID, exerciseID: exercise.exerciseID,
                        count: exercise.sets, targetReps: WorkoutRules.targetReps(exercise.reps)
                    )
                }
            }
            return workoutID
        }
    }

    /// Adds an exercise at the end of the workout, with 3 sets (or as many as last time).
    public func addExercise(_ exerciseID: Int64, toWorkout workoutID: Int64) throws {
        try database.write { db in
            let present = try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM workout_sets WHERE workout_id = ? AND exercise_id = ?", arguments: [workoutID, exerciseID]
            ) ?? 0
            guard present == 0 else { return }
            let previous = try Self.previousSets(db, exerciseID: exerciseID, excluding: workoutID)
            try Self.appendSets(
                db, workoutID: workoutID, exerciseID: exerciseID, count: previous.isEmpty ? 3 : previous.count, targetReps: 10
            )
        }
    }

    /// Adds one set to an exercise of the workout, copying the last one.
    public func addSet(workoutID: Int64, exerciseID: Int64) throws {
        try database.write { db in
            try Self.appendSets(db, workoutID: workoutID, exerciseID: exerciseID, count: 1, targetReps: 10)
        }
    }

    /// Appends `count` sets. Each takes the reps and weight of the set with the same number
    /// last time; else of the last set already here; else `targetReps` and no weight.
    private static func appendSets(_ db: Database, workoutID: Int64, exerciseID: Int64, count: Int, targetReps: Int) throws {
        let existing = try Row.fetchAll(
            db,
            sql: "SELECT position, set_number, reps, weight FROM workout_sets WHERE workout_id = ? AND exercise_id = ? ORDER BY set_number, id",
            arguments: [workoutID, exerciseID]
        )
        let position: Int
        if let first = existing.first {
            position = first["position"]
        } else {
            position = try Int.fetchOne(
                db, sql: "SELECT COALESCE(MAX(position), -1) + 1 FROM workout_sets WHERE workout_id = ?", arguments: [workoutID]
            ) ?? 0
        }
        let previous = try previousSets(db, exerciseID: exerciseID, excluding: workoutID)
        var number: Int = existing.last.map { $0["set_number"] } ?? 0
        var last = existing.last.map { PreviousSet(reps: $0["reps"], weight: $0["weight"]) }
        for _ in 0..<max(count, 0) {
            let before = number < previous.count ? previous[number] : nil
            let values = before ?? last ?? PreviousSet(reps: targetReps, weight: previous.last?.weight ?? 0)
            number += 1
            try db.execute(
                sql: "INSERT INTO workout_sets (workout_id, exercise_id, position, set_number, reps, weight) VALUES (?, ?, ?, ?, ?, ?)",
                arguments: [workoutID, exerciseID, position, number, values.reps, values.weight]
            )
            last = values
        }
    }

    public func updateSet(id: Int64, reps: Int, weight: Double) throws {
        try database.write { db in
            try db.execute(
                sql: "UPDATE workout_sets SET reps = ?, weight = ? WHERE id = ? AND (reps != ? OR weight != ?)",
                arguments: [max(reps, 0), max(weight, 0), id, max(reps, 0), max(weight, 0)]
            )
        }
    }

    /// Marks a set done or not. True when the done set beats the exercise's record
    /// (heaviest done set of the other finished workouts; never on the first time).
    @discardableResult
    public func setDone(id: Int64, _ done: Bool, now: Date = .now, calendar: Calendar = .current) throws -> Bool {
        try database.write { db in
            try db.execute(
                sql: "UPDATE workout_sets SET done = ?, done_at = ? WHERE id = ?",
                arguments: [done ? 1 : 0, done ? LocalTime.timestamp(now, calendar: calendar) : "", id]
            )
            guard done, let row = try Row.fetchOne(
                db, sql: "SELECT workout_id, exercise_id, weight FROM workout_sets WHERE id = ?", arguments: [id]
            ) else { return false }
            let weight: Double = row["weight"]
            guard weight > 0,
                  let record = try Self.record(db, exerciseID: row["exercise_id"], excluding: row["workout_id"])
            else { return false }
            return weight > record
        }
    }

    public func deleteSet(id: Int64) throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM workout_sets WHERE id = ?", arguments: [id])
        }
    }

    public func removeExercise(_ exerciseID: Int64, fromWorkout workoutID: Int64) throws {
        try database.write { db in
            try db.execute(
                sql: "DELETE FROM workout_sets WHERE workout_id = ? AND exercise_id = ?", arguments: [workoutID, exerciseID]
            )
        }
    }

    /// Ends the workout. Sets not done are dropped. A workout with no done set is
    /// discarded and false is returned.
    @discardableResult
    public func finishWorkout(id: Int64, now: Date = .now, calendar: Calendar = .current) throws -> Bool {
        try database.write { db in
            try db.execute(sql: "DELETE FROM workout_sets WHERE workout_id = ? AND done = 0", arguments: [id])
            let done = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM workout_sets WHERE workout_id = ?", arguments: [id]) ?? 0
            guard done > 0 else {
                try db.execute(sql: "DELETE FROM workouts WHERE id = ?", arguments: [id])
                return false
            }
            try db.execute(
                sql: "UPDATE workouts SET finished_at = ? WHERE id = ?",
                arguments: [LocalTime.timestamp(now, calendar: calendar), id]
            )
            return true
        }
    }

    /// Deletes a workout and its sets (a running one, or one of the history).
    public func deleteWorkout(id: Int64) throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM workout_sets WHERE workout_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM workouts WHERE id = ?", arguments: [id])
        }
    }

    public func updateNotes(workoutID: Int64, notes: String) throws {
        try database.write { db in
            try db.execute(
                sql: "UPDATE workouts SET notes = ? WHERE id = ? AND notes != ?", arguments: [notes, workoutID, notes]
            )
        }
    }

    // MARK: History

    /// Finished workouts, newest first.
    public func history(limit: Int = 50, calendar: Calendar = .current) throws -> [WorkoutSummary] {
        try database.read { db in
            try Row.fetchAll(db, sql: """
                SELECT w.id, w.name, w.started_at, w.finished_at,
                       COUNT(DISTINCT s.exercise_id) AS exercises, COUNT(s.id) AS sets,
                       COALESCE(SUM(s.reps * s.weight), 0) AS volume
                FROM workouts w LEFT JOIN workout_sets s ON s.workout_id = w.id AND s.done = 1
                WHERE w.finished_at != ''
                GROUP BY w.id
                ORDER BY w.started_at DESC, w.id DESC
                LIMIT ?
                """, arguments: [limit]).compactMap { row -> WorkoutSummary? in
                guard let started = LocalTime.date(row["started_at"], calendar: calendar),
                      let finished = LocalTime.date(row["finished_at"], calendar: calendar)
                else { return nil }
                return WorkoutSummary(
                    id: row["id"], name: row["name"], startedAt: started, finishedAt: finished,
                    exercises: row["exercises"], sets: row["sets"], volume: row["volume"]
                )
            }
        }
    }

    /// Finished workouts per day ("YYYY-MM-DD"), for the calendar strip.
    public func workoutDays(since: Day) throws -> Set<String> {
        try database.read { db in
            Set(try String.fetchAll(
                db, sql: "SELECT DISTINCT date(started_at) FROM workouts WHERE finished_at != '' AND date(started_at) >= ?",
                arguments: [since.string]
            ))
        }
    }

    /// Done sets of an exercise in each finished workout, newest first.
    public func history(exerciseID: Int64, limit: Int = 30, calendar: Calendar = .current) throws -> ExerciseHistory {
        try database.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT w.id, w.started_at, s.reps, s.weight
                FROM workout_sets s JOIN workouts w ON w.id = s.workout_id
                WHERE s.exercise_id = ? AND s.done = 1 AND w.finished_at != ''
                ORDER BY w.started_at DESC, w.id DESC, s.set_number, s.id
                """, arguments: [exerciseID])
            var entries: [ExerciseHistory.Entry] = []
            var current: (id: Int64, date: Date, sets: [PreviousSet])?
            for row in rows {
                let id: Int64 = row["id"]
                if current?.id != id {
                    if let done = current { entries.append(.init(workoutID: done.id, date: done.date, sets: done.sets)) }
                    guard entries.count < limit else { break }
                    current = (id, LocalTime.date(row["started_at"], calendar: calendar) ?? .distantPast, [])
                }
                current?.sets.append(PreviousSet(reps: row["reps"], weight: row["weight"]))
            }
            if let done = current, entries.count < limit {
                entries.append(.init(workoutID: done.id, date: done.date, sets: done.sets))
            }
            return ExerciseHistory(entries: entries)
        }
    }

    // MARK: Reading a workout

    static func workout(_ db: Database, id: Int64, calendar: Calendar = .current) throws -> Workout? {
        guard let row = try Row.fetchOne(
            db, sql: "SELECT id, plan_id, name, started_at, finished_at, notes FROM workouts WHERE id = ?", arguments: [id]
        ) else { return nil }
        let planID: Int64? = row["plan_id"]
        var rest: [Int64: Int] = [:]
        if let planID {
            for item in try Self.planExercises(db, planID: planID)[planID] ?? [] {
                rest[item.exerciseID] = item.restSeconds
            }
        }
        let sets = try Row.fetchAll(db, sql: """
            SELECT s.id, s.exercise_id, s.position, s.set_number, s.reps, s.weight, s.done, e.name, e.muscle
            FROM workout_sets s JOIN exercises e ON e.id = s.exercise_id
            WHERE s.workout_id = ?
            ORDER BY s.position, s.exercise_id, s.set_number, s.id
            """, arguments: [id])
        var blocks: [WorkoutBlock] = []
        for set in sets {
            let exerciseID: Int64 = set["exercise_id"]
            let item = WorkoutSet(
                id: set["id"], exerciseID: exerciseID, setNumber: set["set_number"], reps: set["reps"],
                weight: set["weight"], done: (set["done"] as Int) != 0
            )
            if blocks.last?.exerciseID == exerciseID {
                blocks[blocks.count - 1].sets.append(item)
            } else {
                let previous = try previousSets(db, exerciseID: exerciseID, excluding: id)
                let best = try record(db, exerciseID: exerciseID, excluding: id)
                blocks.append(WorkoutBlock(
                    exerciseID: exerciseID, name: set["name"], muscle: Muscle(storage: set["muscle"]),
                    position: set["position"], restSeconds: rest[exerciseID] ?? defaultRestSeconds, sets: [item],
                    previous: previous, record: best
                ))
            }
        }
        let finishedText: String = row["finished_at"]
        return Workout(
            id: id,
            planID: planID,
            name: row["name"],
            startedAt: LocalTime.date(row["started_at"], calendar: calendar) ?? .now,
            finishedAt: finishedText.isEmpty ? nil : LocalTime.date(finishedText, calendar: calendar),
            notes: row["notes"],
            blocks: blocks
        )
    }

    /// Done sets of the last finished workout (other than `workoutID`) with the exercise.
    static func previousSets(_ db: Database, exerciseID: Int64, excluding workoutID: Int64) throws -> [PreviousSet] {
        guard let last = try Int64.fetchOne(db, sql: """
            SELECT w.id FROM workouts w JOIN workout_sets s ON s.workout_id = w.id
            WHERE s.exercise_id = ? AND s.done = 1 AND w.finished_at != '' AND w.id != ?
            ORDER BY w.started_at DESC, w.id DESC LIMIT 1
            """, arguments: [exerciseID, workoutID]) else { return [] }
        return try Row.fetchAll(db, sql: """
            SELECT reps, weight FROM workout_sets
            WHERE workout_id = ? AND exercise_id = ? AND done = 1 ORDER BY set_number, id
            """, arguments: [last, exerciseID]).map { PreviousSet(reps: $0["reps"], weight: $0["weight"]) }
    }

    /// Heaviest done set of the other finished workouts. Nil if there is none.
    static func record(_ db: Database, exerciseID: Int64, excluding workoutID: Int64) throws -> Double? {
        try Double.fetchOne(db, sql: """
            SELECT MAX(s.weight) FROM workout_sets s JOIN workouts w ON w.id = s.workout_id
            WHERE s.exercise_id = ? AND s.done = 1 AND w.finished_at != '' AND w.id != ?
            """, arguments: [exerciseID, workoutID])
    }
}
