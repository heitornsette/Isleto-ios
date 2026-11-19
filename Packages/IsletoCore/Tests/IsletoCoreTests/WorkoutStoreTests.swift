import Foundation
import GRDB
import XCTest
@testable import IsletoCore

final class WorkoutStoreTests: XCTestCase {
    private var database: DatabaseQueue!
    private var store: WorkoutStore!
    private let calendar = TestTime.calendar

    override func setUpWithError() throws {
        database = try IsletoDatabase.inMemory()
        store = WorkoutStore(database: database)
    }

    private func catalog(_ name: String) throws -> CatalogExercise {
        try XCTUnwrap(ExerciseCatalog.all.first { $0.name == name })
    }

    /// Runs a whole workout: every set done, then finished.
    private func doWorkout(_ id: Int64, at date: Date) throws {
        let workout = try XCTUnwrap(store.workout(id: id))
        for block in workout.blocks {
            for set in block.sets {
                try store.setDone(id: set.id, true, now: date, calendar: calendar)
            }
        }
        XCTAssertTrue(try store.finishWorkout(id: id, now: date.addingTimeInterval(3600), calendar: calendar))
    }

    func testCatalogIDsAreUniqueValidUUIDs() {
        let ids = ExerciseCatalog.all.map(\.uuid)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertTrue(ids.allSatisfy { UUID(uuidString: $0) != nil })
        XCTAssertEqual(Set(ExerciseCatalog.all.map(\.name)).count, ids.count)
    }

    func testACatalogExerciseIsAddedOnceWithItsFixedUUID() throws {
        let entry = try catalog("Supino reto")
        let first = try store.exerciseID(for: entry)
        let second = try store.exerciseID(for: entry)
        XCTAssertEqual(first, second)
        XCTAssertEqual(try store.exercise(id: first)?.uuid, entry.uuid)
        XCTAssertEqual(try store.exercise(id: first)?.muscle, .chest)
        XCTAssertFalse(try store.catalogNotInLibrary().contains(entry))
    }

    func testRemovingAnExerciseWithHistoryArchivesIt() throws {
        let used = try XCTUnwrap(store.createExercise(name: "Supino", muscle: .chest))
        let unused = try XCTUnwrap(store.createExercise(name: "Remada", muscle: .back))
        let workout = try store.startWorkout(planID: nil, now: TestTime.date(2026, 11, 10, 7), calendar: calendar)
        try store.addExercise(used, toWorkout: workout)
        try doWorkout(workout, at: TestTime.date(2026, 11, 10, 7))

        XCTAssertFalse(try store.removeExercise(id: used))
        XCTAssertTrue(try store.removeExercise(id: unused))
        XCTAssertEqual(try store.exercises().map(\.name), [])
        XCTAssertEqual(try store.exercises(includeArchived: true).map(\.name), ["Supino"])
        XCTAssertEqual(try store.history(calendar: calendar).count, 1, "the history stays")
    }

    func testAPlanKeepsItsExercisesInOrder() throws {
        let plan = try XCTUnwrap(store.createPlan(name: "  Treino A  "))
        let squat = try store.exerciseID(for: catalog("Agachamento livre"))
        let press = try store.exerciseID(for: catalog("Leg press"))
        let first = try store.addExercise(squat, toPlan: plan)
        let second = try store.addExercise(press, toPlan: plan)
        try store.updatePlanExercise(id: first, sets: 4, reps: "8-12", restSeconds: 120)
        try store.reorderPlan(plan, ids: [second, first])

        let saved = try XCTUnwrap(store.plan(id: plan))
        XCTAssertEqual(saved.name, "Treino A")
        XCTAssertEqual(saved.exercises.map(\.name), ["Leg press", "Agachamento livre"])
        XCTAssertEqual(saved.exercises.last?.sets, 4)
        XCTAssertEqual(saved.exercises.last?.reps, "8-12")
        XCTAssertEqual(saved.exercises.last?.restSeconds, 120)
        XCTAssertNil(try store.createPlan(name: "   "))
    }

    func testStartingFromAPlanFillsTheSetsWithLastTime() throws {
        let plan = try XCTUnwrap(store.createPlan(name: "Treino A"))
        let bench = try store.exerciseID(for: catalog("Supino reto"))
        let item = try store.addExercise(bench, toPlan: plan)
        try store.updatePlanExercise(id: item, sets: 3, reps: "8-12", restSeconds: 75)

        // First time: the plan's reps, no weight.
        let first = try store.startWorkout(planID: plan, now: TestTime.date(2026, 11, 10, 7), calendar: calendar)
        var workout = try XCTUnwrap(store.workout(id: first))
        XCTAssertEqual(workout.name, "Treino A")
        XCTAssertEqual(workout.blocks.count, 1)
        XCTAssertEqual(workout.blocks[0].restSeconds, 75)
        XCTAssertEqual(workout.blocks[0].sets.map(\.reps), [8, 8, 8])
        XCTAssertEqual(workout.blocks[0].sets.map(\.weight), [0, 0, 0])
        XCTAssertNil(workout.blocks[0].record)
        let sets = workout.blocks[0].sets
        try store.updateSet(id: sets[0].id, reps: 10, weight: 40)
        try store.updateSet(id: sets[1].id, reps: 9, weight: 42.5)
        try store.updateSet(id: sets[2].id, reps: 8, weight: 42.5)
        try doWorkout(first, at: TestTime.date(2026, 11, 10, 7))

        // Second time: last time's sets, and they are shown as "previous".
        let second = try store.startWorkout(planID: plan, now: TestTime.date(2026, 11, 12, 7), calendar: calendar)
        workout = try XCTUnwrap(store.workout(id: second))
        XCTAssertEqual(workout.blocks[0].sets.map(\.reps), [10, 9, 8])
        XCTAssertEqual(workout.blocks[0].sets.map(\.weight), [40, 42.5, 42.5])
        XCTAssertEqual(workout.blocks[0].previous, [
            PreviousSet(reps: 10, weight: 40), PreviousSet(reps: 9, weight: 42.5), PreviousSet(reps: 8, weight: 42.5),
        ])
        XCTAssertEqual(workout.blocks[0].record, 42.5)
    }

    func testOnlyOneWorkoutRunsAtATime() throws {
        let first = try store.startWorkout(planID: nil, now: TestTime.date(2026, 11, 10, 7), calendar: calendar)
        let again = try store.startWorkout(planID: nil, now: TestTime.date(2026, 11, 10, 8), calendar: calendar)
        XCTAssertEqual(first, again)
        XCTAssertEqual(try store.activeWorkout()?.id, first)
        XCTAssertEqual(try store.activeWorkout()?.name, "Treino livre")
    }

    func testAddingSetsCopiesTheLastOne() throws {
        let bench = try XCTUnwrap(store.createExercise(name: "Supino", muscle: .chest))
        let workout = try store.startWorkout(planID: nil, now: TestTime.date(2026, 11, 10, 7), calendar: calendar)
        try store.addExercise(bench, toWorkout: workout)
        try store.addExercise(bench, toWorkout: workout) // already there: nothing changes
        var sets = try XCTUnwrap(store.workout(id: workout)?.blocks.first?.sets)
        XCTAssertEqual(sets.count, 3)
        try store.updateSet(id: sets[2].id, reps: 6, weight: 50)
        try store.addSet(workoutID: workout, exerciseID: bench)
        sets = try XCTUnwrap(store.workout(id: workout)?.blocks.first?.sets)
        XCTAssertEqual(sets.map(\.setNumber), [1, 2, 3, 4])
        XCTAssertEqual(sets.last?.reps, 6)
        XCTAssertEqual(sets.last?.weight, 50)
    }

    func testExercisesKeepTheOrderTheyWereAdded() throws {
        let workout = try store.startWorkout(planID: nil, now: TestTime.date(2026, 11, 10, 7), calendar: calendar)
        for name in ["Remada", "Supino", "Agachamento"] {
            try store.addExercise(XCTUnwrap(store.createExercise(name: name, muscle: .other)), toWorkout: workout)
        }
        XCTAssertEqual(try store.workout(id: workout)?.blocks.map(\.name), ["Remada", "Supino", "Agachamento"])
    }

    func testARecordIsAHeavierSetThanEveryOtherWorkout() throws {
        let bench = try XCTUnwrap(store.createExercise(name: "Supino", muscle: .chest))
        let first = try store.startWorkout(planID: nil, now: TestTime.date(2026, 11, 10, 7), calendar: calendar)
        try store.addExercise(bench, toWorkout: first)
        let firstSets = try XCTUnwrap(store.workout(id: first)?.blocks.first?.sets)
        for set in firstSets {
            try store.updateSet(id: set.id, reps: 10, weight: 40)
            XCTAssertFalse(try store.setDone(id: set.id, true, calendar: calendar), "no record the first time")
        }
        XCTAssertTrue(try store.finishWorkout(id: first, now: TestTime.date(2026, 11, 10, 8), calendar: calendar))

        let second = try store.startWorkout(planID: nil, now: TestTime.date(2026, 11, 12, 7), calendar: calendar)
        try store.addExercise(bench, toWorkout: second)
        let sets = try XCTUnwrap(store.workout(id: second)?.blocks.first?.sets)
        XCTAssertFalse(try store.setDone(id: sets[0].id, true, calendar: calendar), "same weight is not a record")
        try store.updateSet(id: sets[1].id, reps: 6, weight: 45)
        XCTAssertTrue(try store.setDone(id: sets[1].id, true, calendar: calendar))
    }

    func testFinishingDropsUndoneSetsAndAnEmptyWorkoutIsDiscarded() throws {
        let bench = try XCTUnwrap(store.createExercise(name: "Supino", muscle: .chest))
        let workout = try store.startWorkout(planID: nil, now: TestTime.date(2026, 11, 10, 7), calendar: calendar)
        try store.addExercise(bench, toWorkout: workout)
        let sets = try XCTUnwrap(store.workout(id: workout)?.blocks.first?.sets)
        try store.updateSet(id: sets[0].id, reps: 10, weight: 40)
        try store.setDone(id: sets[0].id, true, calendar: calendar)
        XCTAssertTrue(try store.finishWorkout(id: workout, now: TestTime.date(2026, 11, 10, 8), calendar: calendar))

        let summary = try XCTUnwrap(store.history(calendar: calendar).first)
        XCTAssertEqual(summary.sets, 1)
        XCTAssertEqual(summary.exercises, 1)
        XCTAssertEqual(summary.volume, 400)
        XCTAssertEqual(summary.duration, 3600)
        XCTAssertNil(try store.activeWorkout())

        let empty = try store.startWorkout(planID: nil, now: TestTime.date(2026, 11, 11, 7), calendar: calendar)
        try store.addExercise(bench, toWorkout: empty)
        XCTAssertFalse(try store.finishWorkout(id: empty, calendar: calendar))
        XCTAssertNil(try store.workout(id: empty))
        XCTAssertEqual(try store.history(calendar: calendar).count, 1)
    }

    func testDeletingAPlanKeepsItsWorkouts() throws {
        let plan = try XCTUnwrap(store.createPlan(name: "Treino A"))
        let bench = try store.exerciseID(for: catalog("Supino reto"))
        try store.addExercise(bench, toPlan: plan)
        let workout = try store.startWorkout(planID: plan, now: TestTime.date(2026, 11, 10, 7), calendar: calendar)
        try doWorkout(workout, at: TestTime.date(2026, 11, 10, 7))
        try store.deletePlan(id: plan)
        XCTAssertEqual(try store.plans(), [])
        XCTAssertEqual(try store.history(calendar: calendar).map(\.name), ["Treino A"])
        XCTAssertNil(try store.workout(id: workout)?.planID)
    }

    func testExerciseHistoryIsNewestFirst() throws {
        let bench = try XCTUnwrap(store.createExercise(name: "Supino", muscle: .chest))
        for (day, weight) in [(10, 40.0), (12, 45.0)] {
            let workout = try store.startWorkout(planID: nil, now: TestTime.date(2026, 11, day, 7), calendar: calendar)
            try store.addExercise(bench, toWorkout: workout)
            for set in try XCTUnwrap(store.workout(id: workout)?.blocks.first?.sets) {
                try store.updateSet(id: set.id, reps: 8, weight: weight)
            }
            try doWorkout(workout, at: TestTime.date(2026, 11, day, 7))
        }
        let history = try store.history(exerciseID: bench, calendar: calendar)
        XCTAssertEqual(history.entries.map(\.bestWeight), [45, 40])
        XCTAssertEqual(history.entries.first?.sets.count, 3)
        XCTAssertEqual(history.record, 45)
        XCTAssertEqual(try store.workoutDays(since: Day(TestTime.date(2026, 11, 1), calendar: calendar)), ["2026-11-10", "2026-11-12"])
    }

    func testTargetRepsReadsTheFirstNumber() {
        XCTAssertEqual(WorkoutRules.targetReps("8-12"), 8)
        XCTAssertEqual(WorkoutRules.targetReps("15"), 15)
        XCTAssertEqual(WorkoutRules.targetReps("até a falha"), 10)
        XCTAssertEqual(WorkoutRules.targetReps(" 6 a 8"), 6)
    }

    func testLocalTimeReadsWhatItWrites() {
        let date = TestTime.date(2026, 11, 19, 7, 30)
        XCTAssertEqual(LocalTime.date(LocalTime.timestamp(date, calendar: calendar), calendar: calendar), date)
        XCTAssertEqual(LocalTime.date("2026-11-19", calendar: calendar), TestTime.date(2026, 11, 19, 0))
        XCTAssertNil(LocalTime.date("ontem", calendar: calendar))
    }
}
