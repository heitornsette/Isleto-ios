import IsletoCore
import SwiftUI

/// The workout in progress: each exercise with its sets (kg, reps, done), the rest
/// countdown after a done set, and finishing.
struct ActiveWorkoutView: View {
    let model: WorkoutsModel
    let workoutID: Int64

    @State private var picking = false
    @State private var confirmingFinish = false
    @State private var confirmingDiscard = false
    @State private var historyOf: WorkoutID?
    @FocusState private var focused: SetField?
    @Environment(\.dismiss) private var dismiss
    private var rest: RestTimer { RestTimer.shared }

    private var workout: Workout? { model.workout(id: workoutID) }

    var body: some View {
        NavigationStack {
            Group {
                if let workout {
                    content(workout)
                } else {
                    ContentUnavailableView("Treino encerrado", systemImage: "checkmark.circle")
                }
            }
            .navigationTitle(workout?.name ?? "Treino")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Minimizar", systemImage: "chevron.down") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Finalizar") { confirmingFinish = true }
                        .fontWeight(.bold)
                        .disabled(workout == nil)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("OK") { focused = nil }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if rest.isRunning {
                    RestBanner(rest: rest)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
            }
            .overlay(alignment: .top) {
                if let message = model.recordMessage {
                    Label(message, systemImage: "trophy.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color(hex: "#FBBF24"), in: Capsule())
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .task(id: message) {
                            try? await Task.sleep(for: .seconds(3))
                            guard !Task.isCancelled else { return }
                            withAnimation { model.recordMessage = nil }
                        }
                }
            }
            .animation(.default, value: model.recordMessage)
            .animation(.default, value: rest.isRunning)
            .sheet(isPresented: $picking) {
                ExercisePickerView(model: model, excluded: Set(workout?.blocks.map(\.exerciseID) ?? [])) { exerciseID in
                    model.addExercise(exerciseID, toWorkout: workoutID)
                }
            }
            .sheet(item: $historyOf) { item in
                NavigationStack {
                    ExerciseDetailView(model: model, exerciseID: item.id)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Fechar") { historyOf = nil }
                            }
                        }
                }
            }
            .confirmationDialog(finishTitle, isPresented: $confirmingFinish, titleVisibility: .visible) {
                Button(workout?.doneSets == 0 ? "Descartar treino" : "Finalizar", role: workout?.doneSets == 0 ? .destructive : nil) {
                    _ = model.finish(workoutID)
                    dismiss()
                }
            } message: {
                Text(finishMessage)
            }
            .confirmationDialog("Descartar o treino?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("Descartar", role: .destructive) {
                    model.deleteWorkout(workoutID)
                    dismiss()
                }
            } message: {
                Text("Todas as séries deste treino serão apagadas.")
            }
        }
    }

    private var finishTitle: String {
        workout?.doneSets == 0 ? "Nenhuma série feita" : "Finalizar o treino?"
    }

    private var finishMessage: String {
        guard let workout else { return "" }
        if workout.doneSets == 0 { return "Sem séries feitas, o treino é descartado." }
        let undone = workout.totalSets - workout.doneSets
        return undone > 0
            ? "\(workout.doneSets) séries feitas. As \(undone) não marcadas serão removidas."
            : "\(workout.doneSets) séries, \(Format.volume(workout.volume)) no total."
    }

    private func content(_ workout: Workout) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                header(workout)
                if workout.blocks.isEmpty {
                    Text("Adicione o primeiro exercício.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 24)
                }
                ForEach(workout.blocks) { block in
                    BlockCard(
                        block: block,
                        focused: $focused,
                        onUpdate: { set, reps, weight in model.updateSet(set.id, reps: reps, weight: weight) },
                        onDone: { set, done in model.setDone(set, in: block, done) },
                        onAddSet: { model.addSet(workoutID: workoutID, exerciseID: block.exerciseID) },
                        onDeleteSet: { set in model.deleteSet(set.id) },
                        onRemove: { model.removeExercise(block.exerciseID, fromWorkout: workoutID) },
                        onHistory: { historyOf = WorkoutID(id: block.exerciseID) }
                    )
                }
                Button {
                    picking = true
                } label: {
                    Label("Adicionar exercício", systemImage: "plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .tint(Color.isletoAccent)
                Button("Descartar treino", role: .destructive) { confirmingDiscard = true }
                    .font(.subheadline)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func header(_ workout: Workout) -> some View {
        HStack(spacing: 0) {
            stat(title: "Tempo") {
                Text(workout.startedAt, style: .timer)
            }
            Divider().frame(height: 32)
            stat(title: "Séries") {
                Text("\(workout.doneSets)/\(workout.totalSets)")
            }
            Divider().frame(height: 32)
            stat(title: "Volume") {
                Text(Format.volume(workout.volume))
            }
        }
        .padding(.vertical, 12)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private func stat(title: String, @ViewBuilder value: () -> some View) -> some View {
        VStack(spacing: 2) {
            value()
                .font(.title3.monospacedDigit().weight(.bold))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Which text field has the keyboard: a set's weight or reps.
enum SetField: Hashable {
    case weight(Int64)
    case reps(Int64)
}

/// One exercise of the workout and its sets.
private struct BlockCard: View {
    let block: WorkoutBlock
    var focused: FocusState<SetField?>.Binding
    let onUpdate: (WorkoutSet, Int, Double) -> Void
    let onDone: (WorkoutSet, Bool) -> Void
    let onAddSet: () -> Void
    let onDeleteSet: (WorkoutSet) -> Void
    let onRemove: () -> Void
    let onHistory: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(block.name)
                        .font(.headline)
                    HStack(spacing: 6) {
                        Text(block.muscle.label)
                        if let record = block.record, record > 0 {
                            Text("· recorde \(Format.weight(record))")
                        }
                        Text("· descanso \(Format.rest(block.restSeconds))")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("Histórico", systemImage: "chart.line.uptrend.xyaxis", action: onHistory)
                    Button("Remover exercício", systemImage: "trash", role: .destructive, action: onRemove)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline)
                        .frame(width: 36, height: 28)
                }
            }
            HStack {
                Text("SÉRIE").frame(width: 40, alignment: .leading)
                Text("ANTERIOR").frame(maxWidth: .infinity, alignment: .leading)
                Text("KG").frame(width: 70)
                Text("REPS").frame(width: 56)
                Spacer().frame(width: 40)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            ForEach(Array(block.sets.enumerated()), id: \.element.id) { index, set in
                SetRow(
                    number: index + 1,
                    set: set,
                    previous: index < block.previous.count ? block.previous[index] : nil,
                    focused: focused,
                    onUpdate: { reps, weight in onUpdate(set, reps, weight) },
                    onDone: { done in onDone(set, done) }
                )
                .contextMenu {
                    Button("Apagar série", systemImage: "trash", role: .destructive) { onDeleteSet(set) }
                }
            }
            Button(action: onAddSet) {
                Label("Série", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .tint(.secondary)
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }
}

/// One set: weight and reps fields, and the done button. The fields keep their own text
/// while typing; each change is saved.
private struct SetRow: View {
    let number: Int
    let set: WorkoutSet
    let previous: PreviousSet?
    var focused: FocusState<SetField?>.Binding
    let onUpdate: (Int, Double) -> Void
    let onDone: (Bool) -> Void

    @State private var weightText = ""
    @State private var repsText = ""

    var body: some View {
        HStack {
            Text("\(number)")
                .font(.subheadline.weight(.bold))
                .frame(width: 40, alignment: .leading)
            Text(previous.map { Format.set(reps: $0.reps, weight: $0.weight) } ?? "—")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            TextField("0", text: $weightText)
                .keyboardType(.decimalPad)
                .focused(focused, equals: .weight(set.id))
                .multilineTextAlignment(.center)
                .font(.body.monospacedDigit().weight(.semibold))
                .frame(width: 70, height: 36)
                .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
            TextField("0", text: $repsText)
                .keyboardType(.numberPad)
                .focused(focused, equals: .reps(set.id))
                .multilineTextAlignment(.center)
                .font(.body.monospacedDigit().weight(.semibold))
                .frame(width: 56, height: 36)
                .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
            Button {
                save()
                focused.wrappedValue = nil
                onDone(!set.done)
            } label: {
                Image(systemName: "checkmark")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(set.done ? Color.white : Color.secondary)
                    .frame(width: 36, height: 36)
                    .background(set.done ? Color.isletoAccent : Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
            .accessibilityLabel(set.done ? "Desmarcar série \(number)" : "Concluir série \(number)")
        }
        .padding(.vertical, 2)
        .background(set.done ? Color.isletoAccent.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
        .onAppear {
            weightText = set.weight > 0 ? Format.number(set.weight) : ""
            repsText = set.reps > 0 ? "\(set.reps)" : ""
        }
        .onChange(of: weightText) { _, _ in save() }
        .onChange(of: repsText) { _, _ in save() }
    }

    private func save() {
        guard let weight = Format.parseWeight(weightText) else { return }
        let reps = Int(repsText.trimmingCharacters(in: .whitespaces)) ?? 0
        guard reps != set.reps || weight != set.weight else { return }
        onUpdate(max(reps, 0), weight)
    }
}

/// Countdown of the rest, with ±15 s and skip.
private struct RestBanner: View {
    let rest: RestTimer

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Descanso")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
                if let range = rest.range {
                    Text(timerInterval: range, countsDown: true)
                        .font(.title.monospacedDigit().weight(.bold))
                        .foregroundStyle(.white)
                }
            }
            Spacer()
            control("−15") { rest.add(seconds: -15) }
            control("+15") { rest.add(seconds: 15) }
            control("Pular") { rest.stop() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.isletoAccent, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }

    private func control(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.white.opacity(0.2), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
