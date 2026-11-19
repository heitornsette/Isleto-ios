import Charts
import IsletoCore
import SwiftUI

/// A finished workout: its exercises and sets, notes, and delete.
struct FinishedWorkoutView: View {
    let model: WorkoutsModel
    let workoutID: Int64

    @State private var notes = ""
    @State private var confirmingDelete = false
    @Environment(\.dismiss) private var dismiss

    private var workout: Workout? { model.workout(id: workoutID) }

    var body: some View {
        List {
            if let workout {
                Section {
                    LabeledContent("Data", value: workout.startedAt.formatted(date: .complete, time: .shortened))
                    if let finished = workout.finishedAt {
                        LabeledContent("Duração", value: Format.duration(finished.timeIntervalSince(workout.startedAt)))
                    }
                    LabeledContent("Séries", value: "\(workout.doneSets)")
                    LabeledContent("Volume", value: Format.volume(workout.volume))
                }
                ForEach(workout.blocks) { block in
                    Section {
                        ForEach(Array(block.sets.enumerated()), id: \.element.id) { index, set in
                            HStack {
                                Text("Série \(index + 1)")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(Format.set(reps: set.reps, weight: set.weight))
                                    .monospacedDigit()
                            }
                        }
                    } header: {
                        NavigationLink(value: WorkoutRoute.exercise(block.exerciseID)) {
                            HStack {
                                Text(block.name)
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                            }
                        }
                    }
                }
                Section("Anotações") {
                    TextField("Como foi o treino?", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }
                Section {
                    Button("Apagar treino", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                }
            }
        }
        .navigationTitle(workout?.name ?? "Treino")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { notes = workout?.notes ?? "" }
        .onDisappear { model.updateNotes(workoutID, notes: notes) }
        .confirmationDialog("Apagar este treino?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Apagar", role: .destructive) {
                model.deleteWorkout(workoutID)
                dismiss()
            }
        } message: {
            Text("Ele sai do histórico neste aparelho e nos outros.")
        }
    }
}

/// One exercise: record, a chart of the heaviest set per workout, and every past workout.
struct ExerciseDetailView: View {
    let model: WorkoutsModel
    let exerciseID: Int64

    @State private var history = ExerciseHistory(entries: [])
    @State private var editing = false

    private var exercise: Exercise? { model.exercise(id: exerciseID) }

    var body: some View {
        List {
            Section {
                HStack(spacing: 0) {
                    stat("Recorde", history.record.map(Format.weight) ?? "—")
                    Divider().frame(height: 32)
                    stat("Treinos", "\(history.entries.count)")
                    Divider().frame(height: 32)
                    stat("Última", history.entries.first.map { $0.date.formatted(.dateTime.day().month(.abbreviated)) } ?? "—")
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
            }
            if history.entries.count >= 2 {
                Section("Carga máxima por treino") {
                    Chart(Array(history.entries.reversed())) { entry in
                        LineMark(x: .value("Data", entry.date), y: .value("kg", entry.bestWeight))
                            .foregroundStyle(Color.isletoAccent)
                        PointMark(x: .value("Data", entry.date), y: .value("kg", entry.bestWeight))
                            .foregroundStyle(Color.isletoAccent)
                    }
                    .frame(height: 180)
                    .padding(.vertical, 8)
                }
            }
            Section("Histórico") {
                if history.entries.isEmpty {
                    Text("Ainda sem treinos com este exercício.")
                        .foregroundStyle(.secondary)
                }
                ForEach(history.entries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.subheadline.weight(.semibold))
                        Text(entry.sets.map { Format.set(reps: $0.reps, weight: $0.weight) }.joined(separator: "  ·  "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let notes = exercise?.notes, !notes.isEmpty {
                Section("Anotações") {
                    Text(notes)
                }
            }
        }
        .navigationTitle(exercise?.name ?? "Exercício")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Editar") { editing = true }
                    .disabled(exercise == nil)
            }
        }
        .task { history = model.exerciseHistory(exerciseID) }
        .sheet(isPresented: $editing) {
            if let exercise {
                ExerciseFormView(model: model, exercise: exercise)
            }
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Name, muscle group and notes of an exercise; remove (archive if it has history).
private struct ExerciseFormView: View {
    let model: WorkoutsModel
    let exercise: Exercise

    @State private var name = ""
    @State private var muscle: Muscle = .other
    @State private var notes = ""
    @State private var confirmingRemove = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nome", text: $name)
                Picker("Grupo muscular", selection: $muscle) {
                    ForEach(Muscle.allCases, id: \.self) { muscle in
                        Text(muscle.label).tag(muscle)
                    }
                }
                Section("Anotações") {
                    TextField("Ajuste do aparelho, pegada…", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }
                Section {
                    Button("Remover exercício", systemImage: "trash", role: .destructive) { confirmingRemove = true }
                } footer: {
                    Text("Um exercício com treinos no histórico é só escondido da lista, e o histórico fica.")
                }
            }
            .navigationTitle("Exercício")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        model.updateExercise(exercise.id, name: name, muscle: muscle, notes: notes)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Remover \(exercise.name)?", isPresented: $confirmingRemove, titleVisibility: .visible) {
                Button("Remover", role: .destructive) {
                    _ = model.removeExercise(exercise.id)
                    dismiss()
                }
            }
        }
        .onAppear {
            name = exercise.name
            muscle = exercise.muscle
            notes = exercise.notes
        }
    }
}

/// The exercise library, by muscle group.
struct ExerciseLibraryView: View {
    let model: WorkoutsModel

    @State private var search = ""
    @State private var creating = false
    @State private var newName = ""

    private var filtered: [Exercise] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return model.exercises }
        return model.exercises.filter { $0.name.localizedStandardContains(query) }
    }

    var body: some View {
        List {
            if model.exercises.isEmpty {
                Text("Os exercícios que você usa nas fichas e nos treinos aparecem aqui. O catálogo tem \(ExerciseCatalog.all.count) para escolher.")
                    .foregroundStyle(.secondary)
            }
            ForEach(Muscle.allCases, id: \.self) { muscle in
                let group = filtered.filter { $0.muscle == muscle }
                if !group.isEmpty {
                    Section(muscle.label) {
                        ForEach(group) { exercise in
                            NavigationLink(exercise.name, value: WorkoutRoute.exercise(exercise.id))
                        }
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "Buscar")
        .navigationTitle("Exercícios")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Novo", systemImage: "plus") {
                    newName = ""
                    creating = true
                }
            }
        }
        .alert("Novo exercício", isPresented: $creating) {
            TextField("Nome", text: $newName)
            Button("Criar") { _ = model.createExercise(name: newName, muscle: .other) }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("O grupo muscular pode ser escolhido depois, em Editar.")
        }
    }
}
