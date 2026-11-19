import IsletoCore
import SwiftUI

/// A plan ("ficha"): its name and exercises, with sets, reps and rest of each.
struct PlanEditorView: View {
    let model: WorkoutsModel
    let planID: Int64
    let start: () -> Void

    @State private var name = ""
    @State private var picking = false
    @State private var editing: PlanExercise?
    @State private var confirmingDelete = false
    @Environment(\.dismiss) private var dismiss

    private var plan: WorkoutPlan? { model.plan(id: planID) }

    var body: some View {
        List {
            Section {
                TextField("Nome da ficha", text: $name)
                    .font(.headline)
                    .submitLabel(.done)
                    .onSubmit { model.renamePlan(planID, name: name) }
            }
            Section {
                ForEach(plan?.exercises ?? []) { item in
                    Button {
                        editing = item
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.name)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text("\(item.sets) × \(item.reps) · descanso \(Format.rest(item.restSeconds))")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(item.muscle.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        if let item = plan?.exercises[index] {
                            model.removePlanExercise(item.id)
                        }
                    }
                }
                .onMove { from, to in
                    guard var ids = plan?.exercises.map(\.id) else { return }
                    ids.move(fromOffsets: from, toOffset: to)
                    model.reorderPlan(planID, ids: ids)
                }
                Button("Adicionar exercício", systemImage: "plus.circle.fill") { picking = true }
            } header: {
                Text("Exercícios")
            } footer: {
                Text("Toque num exercício para mudar séries, repetições e descanso. Arraste para reordenar.")
            }
            Section {
                Button {
                    model.renamePlan(planID, name: name)
                    start()
                } label: {
                    Label("Iniciar treino", systemImage: "play.fill")
                        .font(.headline)
                }
                .disabled((plan?.exercises.isEmpty ?? true) || model.active != nil)
                Button("Apagar ficha", systemImage: "trash", role: .destructive) { confirmingDelete = true }
            } footer: {
                if model.active != nil {
                    Text("Termine o treino em andamento para iniciar outro.")
                }
            }
        }
        .navigationTitle(plan?.name ?? "Ficha")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .onAppear { name = plan?.name ?? "" }
        .onDisappear { model.renamePlan(planID, name: name) }
        .sheet(isPresented: $picking) {
            ExercisePickerView(model: model, excluded: Set(plan?.exercises.map(\.exerciseID) ?? [])) { exerciseID in
                model.addExercise(exerciseID, toPlan: planID)
            }
        }
        .sheet(item: $editing) { item in
            PlanExerciseEditor(item: item) { sets, reps, rest in
                model.updatePlanExercise(item.id, sets: sets, reps: reps, restSeconds: rest)
            }
            .presentationDetents([.medium])
        }
        .confirmationDialog("Apagar a ficha?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Apagar", role: .destructive) {
                model.deletePlan(planID)
                dismiss()
            }
        } message: {
            Text("Os treinos já feitos com ela continuam no histórico.")
        }
    }
}

/// Sets, reps and rest of one exercise of a plan.
private struct PlanExerciseEditor: View {
    let item: PlanExercise
    let save: (Int, String, Int) -> Void

    @State private var sets = 3
    @State private var reps = "10"
    @State private var rest = WorkoutStore.defaultRestSeconds
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Stepper("Séries: \(sets)", value: $sets, in: 1...20)
                HStack {
                    Text("Repetições")
                    Spacer()
                    TextField("10", text: $reps)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }
                Stepper("Descanso: \(Format.rest(rest))", value: $rest, in: 0...600, step: 15)
            }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        save(sets, reps, rest)
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            sets = item.sets
            reps = item.reps
            rest = item.restSeconds
        }
    }
}

/// Picks an exercise from the library or the catalog, or creates one.
struct ExercisePickerView: View {
    let model: WorkoutsModel
    /// Already in the plan or workout: not offered.
    let excluded: Set<Int64>
    let pick: (Int64) -> Void

    @State private var search = ""
    @State private var creating = false
    @State private var newName = ""
    @State private var newMuscle: Muscle = .chest
    @Environment(\.dismiss) private var dismiss

    private enum Choice: Identifiable {
        case library(Exercise)
        case catalog(CatalogExercise)

        var id: String {
            switch self {
            case .library(let exercise): "l\(exercise.id)"
            case .catalog(let entry): "c\(entry.uuid)"
            }
        }

        var name: String {
            switch self {
            case .library(let exercise): exercise.name
            case .catalog(let entry): entry.name
            }
        }

        var muscle: Muscle {
            switch self {
            case .library(let exercise): exercise.muscle
            case .catalog(let entry): entry.muscle
            }
        }
    }

    private var choices: [Choice] {
        let library = model.exercises.filter { !excluded.contains($0.id) }.map(Choice.library)
        let catalog = model.catalog.map(Choice.catalog)
        let all = (library + catalog).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return all }
        return all.filter { $0.name.localizedStandardContains(query) || $0.muscle.label.localizedStandardContains(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Criar exercício", systemImage: "plus") {
                        newName = search
                        creating = true
                    }
                }
                ForEach(Muscle.allCases, id: \.self) { muscle in
                    let group = choices.filter { $0.muscle == muscle }
                    if !group.isEmpty {
                        Section(muscle.label) {
                            ForEach(group) { choice in
                                Button {
                                    choose(choice)
                                } label: {
                                    Text(choice.name)
                                        .foregroundStyle(.primary)
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Buscar exercício")
            .navigationTitle("Exercício")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
            .sheet(isPresented: $creating) {
                NavigationStack {
                    Form {
                        TextField("Nome", text: $newName)
                        Picker("Grupo muscular", selection: $newMuscle) {
                            ForEach(Muscle.allCases, id: \.self) { muscle in
                                Text(muscle.label).tag(muscle)
                            }
                        }
                    }
                    .navigationTitle("Novo exercício")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancelar") { creating = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Criar") {
                                if let id = model.createExercise(name: newName, muscle: newMuscle) {
                                    creating = false
                                    pick(id)
                                    dismiss()
                                }
                            }
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
                .presentationDetents([.medium])
            }
        }
    }

    private func choose(_ choice: Choice) {
        switch choice {
        case .library(let exercise):
            pick(exercise.id)
        case .catalog(let entry):
            guard let id = model.exerciseID(for: entry) else { return }
            pick(id)
        }
        dismiss()
    }
}
