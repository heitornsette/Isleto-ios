import IsletoCore
import SwiftUI

@main
struct IsletoApp: App {
    init() {
        // CI screenshots only: sample data before the first screen loads.
        if ProcessInfo.processInfo.arguments.contains("--demo-seed") {
            DemoData.seedIfEmpty()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

enum RootTab: Hashable {
    case today
    case habits
    case workouts

    /// CI screenshots open on a given tab.
    static var initial: RootTab {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--demo-tab-habits") { return .habits }
        if arguments.contains("--demo-tab-workouts") { return .workouts }
        return .today
    }
}

/// The app's sections.
struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = RootTab.initial

    var body: some View {
        TabView(selection: $tab) {
            TodayView()
                .tabItem { Label("Hoje", systemImage: "sun.max.fill") }
                .tag(RootTab.today)
            HabitsView()
                .tabItem { Label("Hábitos", systemImage: "square.grid.3x3.fill") }
                .tag(RootTab.habits)
            WorkoutsView()
                .tabItem { Label("Treino", systemImage: "dumbbell.fill") }
                .tag(RootTab.workouts)
        }
        .tint(Color.isletoAccent)
        .fontDesign(.rounded)
        .onChange(of: scenePhase, initial: true) { _, phase in
            // Every time the app comes to the front: fetch what the desktop changed.
            if phase == .active {
                Task { await CloudSync.shared.syncNow() }
            }
        }
    }
}

/// Sample data for the CI screenshots. Only runs when there are no habits yet.
enum DemoData {
    static func seedIfEmpty() {
        guard let store = try? SharedData.store(),
              let habits = try? store.habits.list(includeArchived: true), habits.isEmpty
        else { return }
        let created = Date.now.addingTimeInterval(-180 * 86_400)
        let today = Day(.now)
        let samples: [(HabitDefinition, Int)] = [
            (HabitDefinition(name: "Corrida matinal", description: "Comece o dia correndo", icon: "figure.run", color: "#A3E635"), 5),
            (HabitDefinition(name: "Beber água", description: "Hidratação ao longo do dia", icon: "drop.fill", color: "#22D3EE", record: .count, target: 8), 6),
            (HabitDefinition(name: "Flexões", icon: "dumbbell.fill", color: "#FBBF24", schedule: .weekdays([1, 3, 5])), 4),
            (HabitDefinition(name: "Ler 20 páginas", description: "Um bom livro", icon: "book.fill", color: "#A78BFA"), 3),
            (HabitDefinition(name: "Refrigerante", icon: "wineglass.fill", color: "#F87171", kind: .quit), 0),
        ]
        for (index, sample) in samples.enumerated() {
            guard let id = try? store.habits.create(sample.0, at: created) else { continue }
            // A fixed pattern, so the screenshots are the same on every run.
            for offset in 1...150 where sample.1 > 0 && (offset * (index + 3)) % 7 < sample.1 {
                let value = sample.0.record == .count ? sample.0.target : 1
                try? store.habits.setValue(id: id, day: today.adding(-offset), value)
            }
            if sample.0.kind == .quit {
                try? store.habits.toggle(id: id, day: today.adding(-12))
            }
        }
        if let first = try? store.habits.list().first {
            try? store.habits.toggle(id: first.id, day: today)
        }
        for _ in 0..<3 {
            try? store.water.add()
        }
        // One finished focus session, so the counter is not zero.
        try? store.focus.start(now: Date.now.addingTimeInterval(-40 * 60))
        try? store.focus.settle()
        seedWorkouts(store.workouts)
    }

    /// Two plans and a few past workouts.
    private static func seedWorkouts(_ workouts: WorkoutStore) {
        let plans: [(String, [String])] = [
            ("Treino A · Peito e tríceps", ["Supino reto", "Supino inclinado", "Crucifixo", "Tríceps corda"]),
            ("Treino B · Costas e bíceps", ["Puxada frontal", "Remada baixa", "Rosca direta"]),
        ]
        var planIDs: [Int64] = []
        for (name, exercises) in plans {
            guard let planID = try? workouts.createPlan(name: name) else { continue }
            planIDs.append(planID)
            for exercise in exercises {
                guard let entry = ExerciseCatalog.all.first(where: { $0.name == exercise }),
                      let id = try? workouts.exerciseID(for: entry),
                      let item = try? workouts.addExercise(id, toPlan: planID)
                else { continue }
                try? workouts.updatePlanExercise(id: item, sets: 3, reps: "8-12", restSeconds: 90)
            }
        }
        // Past workouts, a little heavier each time.
        for (round, daysAgo) in [9, 6, 4, 2].enumerated() {
            let planID = planIDs[round % planIDs.count]
            let start = Date.now.addingTimeInterval(TimeInterval(-daysAgo * 86_400 - 3600))
            guard let id = try? workouts.startWorkout(planID: planID, now: start),
                  let workout = try? workouts.workout(id: id)
            else { continue }
            for (index, block) in workout.blocks.enumerated() {
                for set in block.sets {
                    let weight = Double(20 + index * 5 + round * 2) + (set.setNumber == 3 ? 2.5 : 0)
                    try? workouts.updateSet(id: set.id, reps: 12 - set.setNumber, weight: weight)
                    _ = try? workouts.setDone(id: set.id, true, now: start)
                }
            }
            _ = try? workouts.finishWorkout(id: id, now: start.addingTimeInterval(55 * 60))
        }
    }
}
