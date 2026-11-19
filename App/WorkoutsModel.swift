import Foundation
import IsletoCore
import Observation

/// State of the "Treino" tab. Rules live in IsletoCore (WorkoutStore); this keeps what
/// the screens show, and after each change reloads and schedules a cloud sync.
@MainActor
@Observable
final class WorkoutsModel {
    private(set) var plans: [WorkoutPlan] = []
    private(set) var history: [WorkoutSummary] = []
    private(set) var active: Workout?
    private(set) var exercises: [Exercise] = []
    private(set) var catalog: [CatalogExercise] = []
    /// Days ("YYYY-MM-DD") with a finished workout in the last weeks.
    private(set) var workoutDays: Set<String> = []
    private(set) var errorText: String?
    /// A done set beat the exercise's record: shown for a moment.
    var recordMessage: String?

    func reload() {
        do {
            let store = try SharedData.store().workouts
            plans = try store.plans()
            history = try store.history(limit: 60)
            active = try store.activeWorkout()
            exercises = try store.exercises()
            catalog = try store.catalogNotInLibrary()
            workoutDays = try store.workoutDays(since: Day(.now).adding(-27))
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    /// Runs a change, then reloads the screens and schedules a sync.
    @discardableResult
    private func change<T>(_ work: (WorkoutStore) throws -> T) -> T? {
        var result: T?
        do {
            result = try work(SharedData.store().workouts)
        } catch {
            errorText = error.localizedDescription
        }
        reload()
        CloudSync.shared.scheduleSync()
        return result
    }

    func plan(id: Int64) -> WorkoutPlan? { plans.first { $0.id == id } }

    func workout(id: Int64) -> Workout? {
        if active?.id == id { return active }
        return try? SharedData.store().workouts.workout(id: id)
    }

    func exerciseHistory(_ exerciseID: Int64) -> ExerciseHistory {
        (try? SharedData.store().workouts.history(exerciseID: exerciseID)) ?? ExerciseHistory(entries: [])
    }

    /// Finished workouts in the last 7 days.
    var workoutsThisWeek: Int {
        let since = Day(.now).adding(-6).string
        return workoutDays.filter { $0 >= since }.count
    }

    // MARK: Exercises

    func exerciseID(for entry: CatalogExercise) -> Int64? {
        change { try $0.exerciseID(for: entry) }
    }

    func createExercise(name: String, muscle: Muscle) -> Int64? {
        change { try $0.createExercise(name: name, muscle: muscle) } ?? nil
    }

    func updateExercise(_ id: Int64, name: String, muscle: Muscle, notes: String) {
        change { try $0.updateExercise(id: id, name: name, muscle: muscle, notes: notes) }
    }

    /// True if it was deleted, false if archived (it has history).
    func removeExercise(_ id: Int64) -> Bool {
        change { try $0.removeExercise(id: id) } ?? false
    }

    func exercise(id: Int64) -> Exercise? {
        if let found = exercises.first(where: { $0.id == id }) { return found }
        return try? SharedData.store().workouts.exercise(id: id)
    }

    // MARK: Plans

    func createPlan(name: String) -> Int64? {
        change { try $0.createPlan(name: name) } ?? nil
    }

    func renamePlan(_ id: Int64, name: String) { change { try $0.renamePlan(id: id, name: name) } }
    func deletePlan(_ id: Int64) { change { try $0.deletePlan(id: id) } }
    func addExercise(_ exerciseID: Int64, toPlan planID: Int64) { change { try $0.addExercise(exerciseID, toPlan: planID) } }
    func removePlanExercise(_ id: Int64) { change { try $0.removePlanExercise(id: id) } }
    func reorderPlan(_ planID: Int64, ids: [Int64]) { change { try $0.reorderPlan(planID, ids: ids) } }

    func updatePlanExercise(_ id: Int64, sets: Int, reps: String, restSeconds: Int) {
        change { try $0.updatePlanExercise(id: id, sets: sets, reps: reps, restSeconds: restSeconds) }
    }

    // MARK: Workout in progress

    func start(planID: Int64?) -> Int64? {
        change { try $0.startWorkout(planID: planID) }
    }

    func addExercise(_ exerciseID: Int64, toWorkout workoutID: Int64) {
        change { try $0.addExercise(exerciseID, toWorkout: workoutID) }
    }

    func addSet(workoutID: Int64, exerciseID: Int64) { change { try $0.addSet(workoutID: workoutID, exerciseID: exerciseID) } }
    func deleteSet(_ id: Int64) { change { try $0.deleteSet(id: id) } }
    func updateSet(_ id: Int64, reps: Int, weight: Double) { change { try $0.updateSet(id: id, reps: reps, weight: weight) } }

    func removeExercise(_ exerciseID: Int64, fromWorkout workoutID: Int64) {
        change { try $0.removeExercise(exerciseID, fromWorkout: workoutID) }
    }

    /// Marks a set; a done set starts the rest and may be a new record.
    func setDone(_ set: WorkoutSet, in block: WorkoutBlock, _ done: Bool) {
        let record = change { try $0.setDone(id: set.id, done) } ?? false
        if done {
            RestTimer.shared.begin(seconds: block.restSeconds, exercise: block.name)
            if record {
                recordMessage = "Novo recorde em \(block.name): \(Format.weight(set.weight))"
            }
        } else if RestTimer.shared.isRunning {
            RestTimer.shared.stop()
        }
    }

    /// False if no set was done: the workout was discarded.
    func finish(_ workoutID: Int64) -> Bool {
        RestTimer.shared.stop()
        return change { try $0.finishWorkout(id: workoutID) } ?? false
    }

    func deleteWorkout(_ workoutID: Int64) {
        if active?.id == workoutID {
            RestTimer.shared.stop()
        }
        change { try $0.deleteWorkout(id: workoutID) }
    }

    func updateNotes(_ workoutID: Int64, notes: String) { change { try $0.updateNotes(workoutID: workoutID, notes: notes) } }
}

/// Numbers as the workout screens show them (Brazilian format: "42,5 kg").
enum Format {
    static func weight(_ kg: Double) -> String {
        "\(number(kg)) kg"
    }

    static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "pt_BR")))
    }

    /// "1.250 kg" or "12,4 t".
    static func volume(_ kg: Double) -> String {
        kg >= 10_000 ? "\(number(kg / 1000)) t" : "\(kg.formatted(.number.precision(.fractionLength(0)).locale(Locale(identifier: "pt_BR")))) kg"
    }

    /// "1 h 05 min" or "42 min".
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        return minutes >= 60 ? String(format: "%ld h %02ld min", minutes / 60, minutes % 60) : "\(minutes) min"
    }

    /// "10 × 40 kg" (or "10 reps" with no weight).
    static func set(reps: Int, weight: Double) -> String {
        weight > 0 ? "\(reps) × \(Format.weight(weight))" : "\(reps) reps"
    }

    static func rest(_ seconds: Int) -> String {
        seconds >= 60 ? (seconds % 60 == 0 ? "\(seconds / 60) min" : "\(seconds / 60) min \(seconds % 60) s") : "\(seconds) s"
    }

    /// Reads "42,5" or "42.5". Nil if it is not a number.
    static func parseWeight(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        if cleaned.isEmpty { return 0 }
        return Double(cleaned).map { max(0, $0) }
    }
}
