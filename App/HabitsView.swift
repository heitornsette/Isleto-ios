import Combine
import IsletoCore
import SwiftUI

/// What the habit form edits.
enum HabitEditorTarget: Identifiable {
    case new
    case edit(Habit)

    var id: String {
        switch self {
        case .new: "new"
        case .edit(let habit): "edit-\(habit.id)"
        }
    }
}

/// "Hábitos" tab: category filter and the cards.
struct HabitsView: View {
    @State private var model = HabitsModel()
    @State private var path: [Int64] = []
    @State private var editor: HabitEditorTarget?
    @State private var showingReorder = false
    @State private var showingArchived = false
    @State private var showingCloud = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 12) {
                    if let error = model.errorText {
                        Label(error, systemImage: "xmark.octagon.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !model.categories.isEmpty {
                        categoryChips
                    }
                    if model.habits.isEmpty {
                        emptyState
                    }
                    ForEach(model.visibleHabits) { habit in
                        HabitCardView(habit: habit) { model.tap(habit) }
                            .contentShape(RoundedRectangle(cornerRadius: 20))
                            .onTapGesture { path.append(habit.id) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .navigationTitle("Hábitos")
            .navigationDestination(for: Int64.self) { id in
                HabitDetailView(model: model, habitID: id)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Reordenar", systemImage: "arrow.up.arrow.down") { showingReorder = true }
                            .disabled(model.habits.count < 2)
                        Button("Arquivados (\(model.archived.count))", systemImage: "archivebox") { showingArchived = true }
                        Button("Nuvem", systemImage: "icloud") { showingCloud = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editor = .new
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                    .accessibilityLabel("Novo hábito")
                }
            }
            .sheet(item: $editor) { target in
                HabitFormView(model: model, target: target)
            }
            .sheet(isPresented: $showingReorder) {
                ReorderHabitsView(model: model)
            }
            .sheet(isPresented: $showingArchived) {
                ArchivedHabitsView(model: model)
            }
            .sheet(isPresented: $showingCloud) {
                CloudView()
            }
        }
        .task {
            model.reload()
            await model.syncReminders()
            // CI screenshots only.
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--demo-detail"), let first = model.habits.first {
                path.append(first.id)
            }
            if arguments.contains("--demo-new-habit") {
                editor = .new
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .isletoDataChanged)) { _ in
            model.reload()
        }
        .onChange(of: scenePhase) { _, phase in
            // The widget may have changed the data while the app was in the background.
            if phase == .active { model.reload() }
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("Todos", selected: model.filter == nil) { model.filter = nil }
                ForEach(model.categories) { category in
                    chip(category.name, selected: model.filter == category.id) { model.filter = category.id }
                }
            }
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .foregroundStyle(selected ? Color.white : .primary)
                .background(selected ? Color.isletoAccent : Color(uiColor: .secondarySystemBackground), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.grid.3x3.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.isletoAccent)
            Text("Nenhum hábito ainda")
                .font(.title3.weight(.semibold))
            Text("Crie o primeiro hábito. Cada dia concluído vira um quadrado preenchido.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Criar hábito") { editor = .new }
                .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 48)
        .frame(maxWidth: .infinity)
    }
}

/// Drag to change the order of the list.
struct ReorderHabitsView: View {
    let model: HabitsModel
    @State private var ids: [Int64] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(ids, id: \.self) { id in
                    if let habit = model.habit(id: id) {
                        Label {
                            Text(habit.name)
                        } icon: {
                            Image(systemName: habit.definition.icon)
                                .foregroundStyle(Color(hex: habit.definition.color))
                        }
                    }
                }
                .onMove { ids.move(fromOffsets: $0, toOffset: $1) }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Reordenar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        model.reorder(ids)
                        dismiss()
                    }
                }
            }
            .onAppear { ids = model.habits.map(\.id) }
        }
    }
}

/// Archived habits: bring back or delete.
struct ArchivedHabitsView: View {
    let model: HabitsModel
    @State private var pendingDelete: Habit?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if model.archived.isEmpty {
                    Text("Nenhum hábito arquivado.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.archived) { habit in
                    HStack {
                        HabitIconTile(icon: habit.definition.icon, color: Color(hex: habit.definition.color), size: 32)
                        Text(habit.name)
                        Spacer()
                        Button("Restaurar") { model.setArchived(habit.id, false) }
                            .buttonStyle(.bordered)
                    }
                    .swipeActions {
                        Button("Apagar", role: .destructive) { pendingDelete = habit }
                    }
                }
            }
            .navigationTitle("Arquivados")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
            .confirmationDialog(
                "Apagar \"\(pendingDelete?.name ?? "")\"?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Apagar hábito e histórico", role: .destructive) {
                    if let habit = pendingDelete { model.delete(habit.id) }
                    pendingDelete = nil
                }
            } message: {
                Text("O histórico de dias também é apagado. Não dá para desfazer.")
            }
        }
    }
}
