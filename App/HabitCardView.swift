import IsletoCore
import SwiftUI

/// A habit in the list: icon, name, today's button and the grid of the last weeks.
struct HabitCardView: View {
    let habit: Habit
    let onTap: () -> Void

    private var color: Color { Color(hex: habit.definition.color) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                HabitIconTile(icon: habit.definition.icon, color: color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(habit.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(HabitText.subtitle(habit))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                HabitTapButton(habit: habit, action: onTap)
            }
            HabitGridView(habit: habit)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(color.opacity(0.06))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(color.opacity(0.18), lineWidth: 1)
        }
    }
}

struct HabitIconTile: View {
    let icon: String
    let color: Color
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

/// Today's button: a check box, a ring with "+" for count and measure, or the
/// relapse button of a quit habit.
struct HabitTapButton: View {
    let habit: Habit
    let action: () -> Void

    private var color: Color { Color(hex: habit.definition.color) }

    var body: some View {
        Button(action: action) {
            content
                .frame(width: 42, height: 42)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: habit.todayValue)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var content: some View {
        if habit.definition.kind == .quit {
            let relapsed = habit.relapsed(on: habit.today)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(relapsed ? color : color.opacity(0.12))
                .overlay {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(relapsed ? .white : color)
                }
        } else if habit.definition.record == .check {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(habit.doneToday ? color : color.opacity(0.12))
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(habit.doneToday ? Color.white : color.opacity(0.5))
                }
        } else {
            ZStack {
                Circle().stroke(color.opacity(0.18), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: habit.progressToday)
                    .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: habit.doneToday ? "checkmark" : "plus")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(color)
            }
            .padding(3)
        }
    }

    private var accessibilityText: String {
        if habit.definition.kind == .quit {
            return habit.relapsed(on: habit.today) ? "Desfazer recaída de hoje" : "Marcar recaída hoje"
        }
        return habit.doneToday ? "Concluído hoje" : "Registrar hoje"
    }
}

/// Texts shared by the card and the detail.
enum HabitText {
    static func subtitle(_ habit: Habit) -> String {
        let description = habit.definition.description
        return description.isEmpty ? schedule(habit.definition.schedule) : description
    }

    static func schedule(_ schedule: HabitSchedule) -> String {
        switch schedule {
        case .daily:
            return "Todos os dias"
        case .weekdays(let days):
            if days == Set(1...5) { return "Dias úteis" }
            if days == [6, 7] { return "Fins de semana" }
            return days.sorted().map { weekdayShort[$0 - 1] }.joined(separator: ", ")
        case .timesPerWeek(let times):
            return times == 1 ? "1 vez por semana" : "\(times) vezes por semana"
        }
    }

    static func streak(_ streak: Streak) -> String {
        switch streak.unit {
        case .days: streak.value == 1 ? "1 dia" : "\(streak.value) dias"
        case .weeks: streak.value == 1 ? "1 semana" : "\(streak.value) semanas"
        }
    }

    static func value(_ value: Double, _ definition: HabitDefinition) -> String {
        let number = value.formatted(.number.precision(.fractionLength(0...2)))
        return definition.unit.isEmpty ? number : "\(number) \(definition.unit)"
    }

    static func goal(_ definition: HabitDefinition) -> String? {
        switch definition.record {
        case .check: nil
        case .count, .measure: "Meta: \(value(definition.target, definition))"
        }
    }

    /// Monday first.
    static let weekdayShort = ["seg", "ter", "qua", "qui", "sex", "sáb", "dom"]
    static let weekdayLetter = ["S", "T", "Q", "Q", "S", "S", "D"]
}
