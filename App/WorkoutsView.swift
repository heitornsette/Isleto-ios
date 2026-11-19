import IsletoCore
import SwiftUI

/// Screens reached from the "Treino" tab.
enum WorkoutRoute: Hashable {
    case plan(Int64)
    case finished(Int64)
    case exercise(Int64)
    case library
}

/// "Treino" tab: the running workout, the plans ("fichas") and the history.
struct WorkoutsView: View {
    @State private var model = WorkoutsModel()
    @State private var path: [WorkoutRoute] = []
    @State private var runningWorkout: Int64?
    @State private var askingPlanName = false
    @State private var newPlanName = ""
    @State private var showingCloud = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let error = model.errorText {
                        Label(error, systemImage: "xmark.octagon.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    if let active = model.active {
                        activeCard(active)
                    }
                    weekStrip
                    plansSection
                    historySection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .navigationTitle("Treino")
            .navigationDestination(for: WorkoutRoute.self) { route in
                switch route {
                case .plan(let id): PlanEditorView(model: model, planID: id) { start(planID: id) }
                case .finished(let id): FinishedWorkoutView(model: model, workoutID: id)
                case .exercise(let id): ExerciseDetailView(model: model, exerciseID: id)
                case .library: ExerciseLibraryView(model: model)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Exercícios", systemImage: "list.bullet") { path.append(.library) }
                        Button("Nuvem", systemImage: "icloud") { showingCloud = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        newPlanName = ""
                        askingPlanName = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                    .accessibilityLabel("Nova ficha")
                }
            }
            .alert("Nova ficha", isPresented: $askingPlanName) {
                TextField("Ex.: Treino A, Peito e tríceps", text: $newPlanName)
                Button("Criar") {
                    if let id = model.createPlan(name: newPlanName) {
                        path.append(.plan(id))
                    }
                }
                Button("Cancelar", role: .cancel) {}
            }
            .sheet(isPresented: $showingCloud) {
                CloudView()
            }
            .fullScreenCover(item: Binding(
                get: { runningWorkout.map(WorkoutID.init) },
                set: { runningWorkout = $0?.id }
            )) { item in
                ActiveWorkoutView(model: model, workoutID: item.id)
            }
        }
        .task {
            model.reload()
            runDemo()
        }
        .onReceive(NotificationCenter.default.publisher(for: .isletoDataChanged)) { _ in
            model.reload()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.reload() }
        }
    }

    private func start(planID: Int64?) {
        if let id = model.start(planID: planID) {
            runningWorkout = id
        }
    }

    // MARK: Sections

    private func activeCard(_ workout: Workout) -> some View {
        Button {
            runningWorkout = workout.id
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Color.isletoAccent, in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Treino em andamento")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.isletoAccent)
                    Text(workout.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    HStack(spacing: 4) {
                        Text(workout.startedAt, style: .timer)
                            .monospacedDigit()
                        Text("· \(workout.doneSets)/\(workout.totalSets) séries")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color.isletoAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }

    /// The last 7 days, with a dot on days with a workout.
    private var weekStrip: some View {
        let today = Day(.now)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Últimos 7 dias")
                    .font(.headline)
                Spacer()
                Text(model.workoutsThisWeek == 1 ? "1 treino" : "\(model.workoutsThisWeek) treinos")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.isletoAccent)
            }
            HStack(spacing: 0) {
                ForEach(Array((0..<7).reversed()), id: \.self) { offset in
                    let day = today.adding(-offset)
                    let trained = model.workoutDays.contains(day.string)
                    VStack(spacing: 6) {
                        Text(day.shortWeekdayLabel)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Circle()
                            .fill(trained ? Color.isletoAccent : Color(uiColor: .tertiarySystemFill))
                            .frame(width: 30, height: 30)
                            .overlay {
                                if trained {
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .overlay {
                                if offset == 0 {
                                    Circle().stroke(Color.isletoAccent, lineWidth: 2)
                                }
                            }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private var plansSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Fichas")
                .font(.title3.weight(.bold))
            if model.plans.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Nenhuma ficha ainda")
                        .font(.headline)
                    Text("Monte uma ficha (Treino A, B, C…) com os exercícios, as séries e o descanso, ou comece um treino livre.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Criar ficha", systemImage: "plus") {
                        newPlanName = ""
                        askingPlanName = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.isletoAccent)
                    .padding(.top, 4)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
            }
            ForEach(model.plans) { plan in
                PlanCard(plan: plan, disabled: model.active != nil) {
                    start(planID: plan.id)
                }
                .contentShape(RoundedRectangle(cornerRadius: 20))
                .onTapGesture { path.append(.plan(plan.id)) }
            }
            Button {
                start(planID: nil)
            } label: {
                Label("Treino livre", systemImage: "bolt.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .tint(Color.isletoAccent)
            .disabled(model.active != nil)
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Histórico")
                .font(.title3.weight(.bold))
            if model.history.isEmpty {
                Text("Os treinos finalizados aparecem aqui.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(model.history) { item in
                Button {
                    path.append(.finished(item.id))
                } label: {
                    HistoryRow(item: item)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: CI screenshots

    private func runDemo() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--demo-workout") {
            // A workout in progress: two sets done, so the rest countdown shows.
            if model.active == nil, let plan = model.plans.first, let id = model.start(planID: plan.id),
               let block = model.workout(id: id)?.blocks.first {
                for set in block.sets.prefix(2) {
                    model.setDone(set, in: block, true)
                }
            }
            runningWorkout = model.active?.id
        }
        if arguments.contains("--demo-plan"), let plan = model.plans.first {
            path.append(.plan(plan.id))
        }
        if arguments.contains("--demo-exercise"), let first = model.history.first,
           let workout = model.workout(id: first.id), let block = workout.blocks.first {
            path.append(.exercise(block.exerciseID))
        }
    }
}

/// Identifiable wrapper for `fullScreenCover(item:)`.
struct WorkoutID: Identifiable {
    let id: Int64
}

private struct PlanCard: View {
    let plan: WorkoutPlan
    let disabled: Bool
    let start: () -> Void

    private var muscles: String {
        var seen: [Muscle] = []
        for item in plan.exercises where !seen.contains(item.muscle) {
            seen.append(item.muscle)
        }
        return seen.map(\.label).joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(plan.name)
                    .font(.headline)
                Text(plan.exercises.count == 1 ? "1 exercício" : "\(plan.exercises.count) exercícios")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !muscles.isEmpty {
                    Text(muscles)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button(action: start) {
                Image(systemName: "play.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(disabled ? Color.gray : Color.isletoAccent, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(disabled || plan.exercises.isEmpty)
            .accessibilityLabel("Iniciar \(plan.name)")
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }
}

struct HistoryRow: View {
    let item: WorkoutSummary

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(item.startedAt.formatted(.dateTime.day()))
                    .font(.title3.weight(.bold))
                Text(item.startedAt.formatted(.dateTime.month(.abbreviated)).uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.headline)
                Text("\(Format.duration(item.duration)) · \(item.sets) séries · \(Format.volume(item.volume))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

extension Day {
    /// "S", "T", "Q"… for the week strip (Monday = 1).
    var shortWeekdayLabel: String {
        ["S", "T", "Q", "Q", "S", "S", "D"][(weekday - 1 + 7) % 7]
    }
}
