import SwiftUI
import WidgetKit

struct CounterEntry: TimelineEntry {
    let date: Date
    let value: Int?
    let message: String?
}

struct CounterProvider: TimelineProvider {
    func placeholder(in context: Context) -> CounterEntry {
        CounterEntry(date: .now, value: 0, message: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (CounterEntry) -> Void) {
        completion(load())
    }

    /// One entry and `.never`: the widget is refreshed when the app or the "+1"
    /// button calls `WidgetCenter.reloadAllTimelines()`.
    func getTimeline(in context: Context, completion: @escaping (Timeline<CounterEntry>) -> Void) {
        completion(Timeline(entries: [load()], policy: .never))
    }

    private func load() -> CounterEntry {
        do {
            return CounterEntry(date: .now, value: try SharedData.counter().value(), message: nil)
        } catch {
            return CounterEntry(date: .now, value: nil, message: error.localizedDescription)
        }
    }
}

struct CounterWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CounterWidget", provider: CounterProvider()) { entry in
            CounterWidgetView(value: entry.value, message: entry.message)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Contador de teste")
        .description("Lê o contador do App Group e soma 1.")
        .supportedFamilies([.systemSmall])
    }
}
