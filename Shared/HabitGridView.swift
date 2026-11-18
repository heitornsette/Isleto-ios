import IsletoCore
import SwiftUI

/// Grid of squares, one column per week (Monday on top), newest week on the right.
/// A filled square is a completed day. Drawn with Canvas: one view, not hundreds.
struct HabitGridView: View {
    let habit: Habit
    /// Number of weeks; nil fills the available width.
    var weeks: Int?
    var cell: CGFloat = 9
    var spacing: CGFloat = 3

    var body: some View {
        GeometryReader { proxy in
            let columns = weeks ?? max(1, Int((proxy.size.width + spacing) / (cell + spacing)))
            Canvas { context, _ in
                draw(context, columns: columns)
            }
        }
        .frame(height: cell * 7 + spacing * 6)
    }

    private func draw(_ context: GraphicsContext, columns: Int) {
        let color = Color(hex: habit.definition.color)
        let firstWeek = habit.today.startOfWeek.adding(-7 * (columns - 1))
        for column in 0..<columns {
            for row in 0..<7 {
                let day = firstWeek.adding(column * 7 + row)
                guard day <= habit.today else { continue }
                let rect = CGRect(
                    x: CGFloat(column) * (cell + spacing),
                    y: CGFloat(row) * (cell + spacing),
                    width: cell,
                    height: cell
                )
                let shape = Path(roundedRect: rect, cornerRadius: cell * 0.28)
                context.fill(shape, with: .color(habit.isComplete(day) ? color : color.opacity(0.16)))
            }
        }
    }
}

/// The current week, Monday to Sunday, in one row. For the widget.
struct HabitWeekRow: View {
    let habit: Habit
    var size: CGFloat = 11

    var body: some View {
        let color = Color(hex: habit.definition.color)
        let monday = habit.today.startOfWeek
        HStack(spacing: 3) {
            ForEach(0..<7, id: \.self) { offset in
                let day = monday.adding(offset)
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(day > habit.today ? color.opacity(0.06) : habit.isComplete(day) ? color : color.opacity(0.18))
                    .frame(width: size, height: size)
            }
        }
    }
}
