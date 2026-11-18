import AppIntents
import IsletoCore
import SwiftUI

/// Content of the medium "Hoje" widget. Also drawn inside the app (Diagnóstico),
/// so the CI screenshots show it without adding the widget to a home screen.
struct TodayWidgetView: View {
    /// nil when the shared database could not be read.
    let summary: DaySummary?
    let message: String?

    var body: some View {
        if let summary {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    water(summary)
                    focus(summary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                habits(summary.habits)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(spacing: 6) {
                Label("Isleto", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                Text(message ?? "Sem dados")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func water(_ summary: DaySummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Água", systemImage: "drop.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.isletoWater)
            Text("\(summary.waterMl) / \(summary.waterGoalMl) ml")
                .font(.caption.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            ProgressView(value: summary.waterProgress)
                .tint(Color.isletoWater)
            Button(intent: AddWaterIntent()) {
                Text("+\(WaterStore.glassMl) ml")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.isletoWater)
        }
    }

    @ViewBuilder
    private func focus(_ summary: DaySummary) -> some View {
        if let active = summary.activeFocus {
            HStack(spacing: 4) {
                Image(systemName: "timer").foregroundStyle(Color.isletoFocus)
                Text(timerInterval: active.range, countsDown: true)
                    .font(.caption.monospacedDigit().weight(.semibold))
            }
        } else {
            Label("\(summary.focusSessions) foco(s) hoje", systemImage: "timer")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func habits(_ habits: [Habit]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Hábitos", systemImage: "checkmark.seal.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.isletoHabit)
            if habits.isEmpty {
                Text("Adicione hábitos no app.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            // The current week of each habit; a tap records today (check, relapse, +1).
            ForEach(habits.prefix(4)) { habit in
                Button(intent: ToggleHabitIntent(habitID: habit.id)) {
                    HStack(spacing: 6) {
                        Image(systemName: habit.definition.icon)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color(hex: habit.definition.color))
                            .frame(width: 14)
                        HabitWeekRow(habit: habit, size: 10)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(habit.name)
            }
        }
    }
}
