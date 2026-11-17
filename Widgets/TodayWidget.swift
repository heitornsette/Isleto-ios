import IsletoCore
import SwiftUI
import WidgetKit

struct TodayEntry: TimelineEntry {
    let date: Date
    let summary: DaySummary?
    let message: String?
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(
            date: .now,
            summary: DaySummary(waterMl: 750, waterGoalMl: WaterStore.goalMl, focusSessions: 1, activeFocus: nil, habits: []),
            message: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(load(now: .now))
    }

    /// The app and the buttons reload the widget after each change. Besides that,
    /// it refreshes when a focus session ends (to count it) and at midnight
    /// (today's totals start over).
    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let now = Date.now
        let entry = load(now: now)
        var next = LocalTime.startOfNextDay(after: now)
        if let end = entry.summary?.activeFocus?.end, end < next {
            next = end.addingTimeInterval(1)
        }
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func load(now: Date) -> TodayEntry {
        do {
            return TodayEntry(date: now, summary: try SharedData.store().today(now: now), message: nil)
        } catch {
            return TodayEntry(date: now, summary: nil, message: error.localizedDescription)
        }
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayWidget", provider: TodayProvider()) { entry in
            TodayWidgetView(summary: entry.summary, message: entry.message)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Hoje")
        .description("Água, foco e hábitos do dia, com botões.")
        .supportedFamilies([.systemMedium])
    }
}
