import IsletoCore
import SwiftUI

/// A habit opened from the list: map of the last weeks, streak and a month calendar
/// where tapping a day records it.
struct HabitDetailView: View {
    let model: HabitsModel
    let habitID: Int64

    /// First day of the month shown in the calendar.
    @State private var month: Day?
    @State private var editor: HabitEditorTarget?
    @State private var confirmingDelete = false
    @State private var valueDay: Day?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let habit = model.habit(id: habitID) {
            content(habit)
        } else {
            ContentUnavailableView("Hábito apagado", systemImage: "trash")
        }
    }

    private func content(_ habit: Habit) -> some View {
        let color = Color(hex: habit.definition.color)
        let shownMonth = month ?? Self.firstOfMonth(habit.today)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(habit, color: color)
                HabitHeatmapView(habit: habit)
                    .padding(14)
                    .background(color.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(color.opacity(0.18))
                    }
                chips(habit, color: color)
                calendar(habit, month: shownMonth, color: color)
            }
            .padding(16)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    editor = .edit(habit)
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("Editar")
                Menu {
                    Button(habit.archived ? "Restaurar" : "Arquivar", systemImage: "archivebox") {
                        model.setArchived(habit.id, !habit.archived)
                        if !habit.archived { dismiss() }
                    }
                    Button("Apagar", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Opções")
            }
        }
        .sheet(item: $editor) { target in
            HabitFormView(model: model, target: target)
        }
        .sheet(item: Binding(
            get: { valueDay.map { DayValueTarget(day: $0) } },
            set: { valueDay = $0?.day }
        )) { target in
            DayValueEditor(habit: habit, day: target.day) { value in
                model.setValue(habit.id, day: target.day, value)
            }
            .presentationDetents([.height(280)])
        }
        .confirmationDialog("Apagar \"\(habit.name)\"?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Apagar hábito e histórico", role: .destructive) {
                model.delete(habit.id)
                dismiss()
            }
        } message: {
            Text("O histórico de dias também é apagado. Para guardar o histórico, use Arquivar.")
        }
    }

    private func header(_ habit: Habit, color: Color) -> some View {
        HStack(spacing: 14) {
            HabitIconTile(icon: habit.definition.icon, color: color, size: 60)
            VStack(alignment: .leading, spacing: 4) {
                Text(habit.name)
                    .font(.title2.weight(.bold))
                Text(habit.definition.description.isEmpty ? "Sem descrição" : habit.definition.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func chips(_ habit: Habit, color: Color) -> some View {
        HStack(spacing: 8) {
            chip(HabitText.streak(habit.streak), icon: "flame.fill", color: color)
            chip(HabitText.schedule(habit.definition.schedule), icon: "repeat", color: color)
            if let goal = HabitText.goal(habit.definition) {
                chip(goal, icon: "target", color: color)
            }
            if habit.definition.kind == .quit {
                chip("Largar", icon: "hand.raised.fill", color: color)
            }
        }
    }

    private func chip(_ text: String, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.monospaced().weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
    }

    // MARK: Calendar

    private func calendar(_ habit: Habit, month: Day, color: Color) -> some View {
        let days = Self.days(inMonthOf: month)
        let blanks = month.weekday - 1
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        return VStack(spacing: 12) {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(0..<7, id: \.self) { index in
                    Text(HabitText.weekdayShort[index] + ".")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                ForEach(0..<blanks, id: \.self) { _ in
                    Color.clear.frame(height: 40)
                }
                ForEach(0..<days, id: \.self) { offset in
                    dayCell(habit, day: month.adding(offset), color: color)
                }
            }
            HStack {
                Text(Self.monthTitle(month))
                    .font(.subheadline.monospaced())
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                Spacer()
                Button("Hoje") { self.month = Self.firstOfMonth(habit.today) }
                    .buttonStyle(.bordered)
                Button {
                    self.month = Self.firstOfMonth(month.adding(-1))
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.bordered)
                Button {
                    self.month = month.adding(days)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.bordered)
                .disabled(month.adding(days) > habit.today)
            }
            Text(habit.definition.record == .check ? "Toque num dia para marcar ou desmarcar." : "Toque num dia para registrar o valor.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func dayCell(_ habit: Habit, day: Day, color: Color) -> some View {
        let future = day > habit.today
        let complete = habit.isComplete(day)
        let marked = habit.value(on: day) > 0
        return Button {
            if habit.definition.record == .check {
                model.toggle(habit.id, day: day)
            } else {
                valueDay = day
            }
        } label: {
            VStack(spacing: 2) {
                Text("\(day.components.day)")
                    .font(.body.monospacedDigit().weight(complete ? .bold : .regular))
                    .foregroundStyle(future ? Color.secondary.opacity(0.4) : complete ? Color.white : Color.primary)
                Circle()
                    .fill(marked ? (complete ? Color.white : color) : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(complete ? color : Color.clear)
            }
            .overlay {
                if day == habit.today {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(color, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(future)
    }

    // MARK: Month math

    static func firstOfMonth(_ day: Day) -> Day {
        day.adding(1 - day.components.day)
    }

    static func days(inMonthOf first: Day) -> Int {
        let c = first.components
        let next = c.month == 12 ? (c.year + 1, 1) : (c.year, c.month + 1)
        let nextFirst = Day(String(format: "%04ld-%02ld-01", next.0, next.1)) ?? first.adding(30)
        return nextFirst.number - first.number
    }

    static func monthTitle(_ day: Day) -> String {
        let names = ["jan.", "fev.", "mar.", "abr.", "mai.", "jun.", "jul.", "ago.", "set.", "out.", "nov.", "dez."]
        let c = day.components
        return "\(names[c.month - 1]) de \(c.year)"
    }
}

private struct DayValueTarget: Identifiable {
    let day: Day
    var id: Int { day.number }
}

/// Value of one day for count and measure habits.
struct DayValueEditor: View {
    let habit: Habit
    let day: Day
    let onSave: (Double) -> Void
    @State private var text = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("0", text: $text)
                            .keyboardType(.decimalPad)
                            .font(.title.monospacedDigit())
                        if !habit.definition.unit.isEmpty {
                            Text(habit.definition.unit).foregroundStyle(.secondary)
                        }
                    }
                    if habit.definition.record == .count {
                        Stepper("Ajustar", onIncrement: { step(1) }, onDecrement: { step(-1) })
                    }
                } footer: {
                    Text(HabitText.goal(habit.definition) ?? "")
                }
            }
            .navigationTitle(day.date().formatted(date: .abbreviated, time: .omitted))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        onSave(Self.parse(text))
                        dismiss()
                    }
                }
            }
            .onAppear {
                let value = habit.value(on: day)
                text = value > 0 ? value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never)) : ""
            }
        }
    }

    private func step(_ amount: Double) {
        text = max(0, Self.parse(text) + amount).formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
    }

    /// Accepts "2,5" and "2.5".
    static func parse(_ text: String) -> Double {
        Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)) ?? 0
    }
}

/// The map of the last weeks with month names on top and weekday names on the left.
struct HabitHeatmapView: View {
    let habit: Habit
    private let cell: CGFloat = 11
    private let spacing: CGFloat = 3
    private let labelWidth: CGFloat = 30

    var body: some View {
        GeometryReader { proxy in
            let columns = max(1, Int((proxy.size.width - labelWidth + spacing) / (cell + spacing)))
            let firstWeek = habit.today.startOfWeek.adding(-7 * (columns - 1))
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topLeading) {
                    ForEach(monthLabels(firstWeek: firstWeek, columns: columns), id: \.column) { label in
                        Text(label.text)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .offset(x: labelWidth + CGFloat(label.column) * (cell + spacing))
                    }
                }
                .frame(height: 14, alignment: .topLeading)
                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: spacing) {
                        ForEach(0..<7, id: \.self) { row in
                            Text(row % 2 == 1 ? HabitText.weekdayShort[row].capitalized : "")
                                .font(.system(size: 9).monospaced())
                                .foregroundStyle(.secondary)
                                .frame(height: cell)
                        }
                    }
                    .frame(width: labelWidth, alignment: .leading)
                    HabitGridView(habit: habit, weeks: columns, cell: cell, spacing: spacing)
                }
            }
        }
        .frame(height: 14 + 6 + cell * 7 + spacing * 6)
    }

    private struct MonthLabel {
        let column: Int
        let text: String
    }

    /// A label over the first week of each month, skipped if too close to the previous one.
    private func monthLabels(firstWeek: Day, columns: Int) -> [MonthLabel] {
        let names = ["Jan.", "Fev.", "Mar.", "Abr.", "Mai.", "Jun.", "Jul.", "Ago.", "Set.", "Out.", "Nov.", "Dez."]
        var labels: [MonthLabel] = []
        for column in 0..<columns {
            let start = firstWeek.adding(column * 7)
            let monthDay = (0..<7).map { start.adding($0) }.first { $0.components.day == 1 }
            guard let monthDay else { continue }
            if let last = labels.last, column - last.column < 3 { continue }
            labels.append(MonthLabel(column: column, text: names[monthDay.components.month - 1]))
        }
        return labels
    }
}
