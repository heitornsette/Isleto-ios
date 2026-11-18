import IsletoCore
import SwiftUI

/// Create or edit a habit: icon, name, description, color, type, repetition,
/// record, reminders and categories.
struct HabitFormView: View {
    let model: HabitsModel
    let target: HabitEditorTarget

    @State private var definition = HabitDefinition(icon: "checkmark", color: "#3AA76D")
    @State private var scheduleMode: ScheduleMode = .daily
    @State private var weekdays: Set<Int> = [1, 2, 3, 4, 5]
    @State private var timesPerWeek = 3
    @State private var reminderDates: [Date] = []
    @State private var newCategory = ""
    @State private var loaded = false
    @Environment(\.dismiss) private var dismiss

    enum ScheduleMode: String, CaseIterable, Identifiable {
        case daily = "Todo dia"
        case weekdays = "Dias"
        case weekly = "Vezes"
        var id: String { rawValue }
    }

    private var color: Color { Color(hex: definition.color) }
    private var canSave: Bool { !definition.name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                iconSection
                Section("Nome") {
                    TextField("Ex.: Ler 20 páginas", text: $definition.name)
                        .onChange(of: definition.name) { _, name in
                            if name.count > HabitDefinition.maxNameLength {
                                definition.name = String(name.prefix(HabitDefinition.maxNameLength))
                            }
                        }
                    TextField("Descrição (opcional)", text: $definition.description, axis: .vertical)
                        .lineLimit(1...3)
                }
                colorSection
                Section {
                    Picker("Tipo de hábito", selection: $definition.kind) {
                        Text("Criar").tag(HabitKind.build)
                        Text("Largar").tag(HabitKind.quit)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Tipo de hábito")
                } footer: {
                    Text(definition.kind == .build
                        ? "Marque cada dia em que você o concluiu."
                        : "Marque o dia em que recaiu. A sequência conta os dias desde a última recaída.")
                }
                scheduleSection
                if definition.kind == .build {
                    recordSection
                }
                remindersSection
                categoriesSection
            }
            .navigationTitle(isNew ? "Novo hábito" : "Editar hábito")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: save) {
                    Text("Salvar")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(canSave ? Color.isletoAccent : Color.gray, in: Capsule())
                }
                .disabled(!canSave)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
            .onAppear(perform: load)
        }
    }

    private var isNew: Bool {
        if case .new = target { return true }
        return false
    }

    // MARK: Sections

    private var iconSection: some View {
        Section {
            VStack(spacing: 14) {
                HabitIconTile(icon: definition.icon, color: color, size: 84)
                    .frame(maxWidth: .infinity)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 8) {
                    ForEach(HabitPalette.icons, id: \.self) { icon in
                        Button {
                            definition.icon = icon
                        } label: {
                            Image(systemName: icon)
                                .font(.system(size: 17))
                                .frame(width: 34, height: 34)
                                .foregroundStyle(definition.icon == icon ? Color.white : color)
                                .background(
                                    definition.icon == icon ? color : color.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(icon)
                    }
                }
            }
            .padding(.vertical, 6)
        } header: {
            Text("Ícone")
        }
    }

    private var colorSection: some View {
        Section("Cor") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 7), spacing: 10) {
                ForEach(HabitPalette.colors, id: \.self) { hex in
                    Button {
                        definition.color = hex
                    } label: {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(hex: hex))
                            .frame(height: 36)
                            .overlay {
                                if definition.color == hex {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(Color.primary, lineWidth: 2)
                                        .padding(-4)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cor \(hex)")
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var scheduleSection: some View {
        Section {
            Picker("Repetição", selection: $scheduleMode) {
                ForEach(ScheduleMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            switch scheduleMode {
            case .daily:
                EmptyView()
            case .weekdays:
                HStack(spacing: 6) {
                    ForEach(1...7, id: \.self) { day in
                        let on = weekdays.contains(day)
                        Button {
                            if on { weekdays.remove(day) } else { weekdays.insert(day) }
                        } label: {
                            Text(HabitText.weekdayLetter[day - 1])
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .foregroundStyle(on ? Color.white : .primary)
                                .background(on ? color : color.opacity(0.12), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(HabitText.weekdayShort[day - 1])
                    }
                }
            case .weekly:
                Stepper(timesPerWeek == 1 ? "1 vez por semana" : "\(timesPerWeek) vezes por semana", value: $timesPerWeek, in: 1...6)
            }
        } header: {
            Text("Repetição")
        } footer: {
            switch scheduleMode {
            case .daily: Text("Todos os dias.")
            case .weekdays: Text(weekdays.isEmpty ? "Escolha pelo menos um dia." : "Só nos dias marcados. Os outros não quebram a sequência.")
            case .weekly: Text("Em quaisquer dias da semana (segunda a domingo). A sequência conta semanas.")
            }
        }
    }

    private var recordSection: some View {
        Section {
            Picker("Registro", selection: $definition.record) {
                Text("Sim / Não").tag(HabitRecord.check)
                Text("Contagem").tag(HabitRecord.count)
                Text("Medida").tag(HabitRecord.measure)
            }
            .pickerStyle(.segmented)
            switch definition.record {
            case .check:
                EmptyView()
            case .count:
                Stepper("Meta: \(Int(definition.target)) por dia", value: $definition.target, in: 1...999, step: 1)
            case .measure:
                HStack {
                    Text("Meta")
                    TextField("5", value: $definition.target, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                    TextField("unidade", text: $definition.unit)
                        .frame(width: 90)
                }
            }
        } header: {
            Text("Registro")
        } footer: {
            switch definition.record {
            case .check: Text("Marque o dia: feito ou não feito.")
            case .count: Text("Cada toque soma 1. O dia conta quando chega na meta.")
            case .measure: Text("Registre um valor, por exemplo 5 km. O dia conta quando chega na meta.")
            }
        }
    }

    private var remindersSection: some View {
        Section {
            ForEach(reminderDates.indices, id: \.self) { index in
                DatePicker("Lembrete \(index + 1)", selection: $reminderDates[index], displayedComponents: .hourAndMinute)
            }
            .onDelete { reminderDates.remove(atOffsets: $0) }
            if reminderDates.count < HabitDefinition.maxReminders {
                Button("Adicionar lembrete", systemImage: "bell.badge") {
                    reminderDates.append(Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now)
                }
            }
        } header: {
            Text("Lembretes")
        } footer: {
            Text(reminderDates.isEmpty ? "Sem lembretes." : "Notificação nos dias previstos. Deslize para remover.")
        }
    }

    private var categoriesSection: some View {
        Section {
            ForEach(model.categories) { category in
                let on = definition.categoryIDs.contains(category.id)
                Button {
                    if on { definition.categoryIDs.remove(category.id) } else { definition.categoryIDs.insert(category.id) }
                } label: {
                    HStack {
                        Text(category.name).foregroundStyle(.primary)
                        Spacer()
                        if on { Image(systemName: "checkmark").foregroundStyle(color) }
                    }
                }
                .swipeActions {
                    Button("Apagar", role: .destructive) {
                        definition.categoryIDs.remove(category.id)
                        model.deleteCategory(category.id)
                    }
                }
            }
            HStack {
                TextField("Nova categoria", text: $newCategory)
                    .onSubmit(addCategory)
                Button("Criar", action: addCategory)
                    .disabled(newCategory.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Categorias")
        } footer: {
            Text(model.categories.isEmpty
                ? "Crie categorias como Saúde ou Estudo para filtrar a lista."
                : "Toque para incluir. Deslize para apagar a categoria.")
        }
    }

    // MARK: Actions

    private func addCategory() {
        if let id = model.createCategory(newCategory) {
            definition.categoryIDs.insert(id)
        }
        newCategory = ""
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard case .edit(let habit) = target else { return }
        definition = habit.definition
        switch habit.definition.schedule {
        case .daily:
            scheduleMode = .daily
        case .weekdays(let days):
            scheduleMode = .weekdays
            weekdays = days
        case .timesPerWeek(let times):
            scheduleMode = .weekly
            timesPerWeek = times
        }
        reminderDates = habit.definition.reminders.compactMap {
            Calendar.current.date(bySettingHour: $0.hour, minute: $0.minute, second: 0, of: .now)
        }
    }

    private func save() {
        var result = definition
        switch scheduleMode {
        case .daily: result.schedule = .daily
        case .weekdays: result.schedule = weekdays.isEmpty ? .daily : .weekdays(weekdays)
        case .weekly: result.schedule = .timesPerWeek(timesPerWeek)
        }
        result.reminders = reminderDates.map {
            let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
            return ReminderTime(hour: c.hour ?? 9, minute: c.minute ?? 0)
        }
        let saved: Bool = switch target {
        case .new: model.create(result)
        case .edit(let habit): model.update(habit.id, result)
        }
        if saved { dismiss() }
    }
}
