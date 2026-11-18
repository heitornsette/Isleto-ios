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
}

/// The app's sections. More tabs (workouts...) come later.
struct RootView: View {
    @State private var tab: RootTab = ProcessInfo.processInfo.arguments.contains("--demo-tab-habits") ? .habits : .today

    var body: some View {
        TabView(selection: $tab) {
            TodayView()
                .tabItem { Label("Hoje", systemImage: "sun.max.fill") }
                .tag(RootTab.today)
            HabitsView()
                .tabItem { Label("Hábitos", systemImage: "square.grid.3x3.fill") }
                .tag(RootTab.habits)
        }
        .tint(Color.isletoAccent)
        .fontDesign(.rounded)
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
    }
}
