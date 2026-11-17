import ActivityKit
import SwiftUI
import WidgetKit

/// Live Activity of the focus session, on the lock screen and in the Dynamic Island.
///
/// Only system timers (`Text(timerInterval:)`, `ProgressView(timerInterval:)`):
/// they keep counting with the app closed. A free Apple ID has no push, so nothing
/// else could update this view.
struct TimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerActivityAttributes.self) { context in
            LockScreenTimerView(title: context.attributes.title, range: context.state.range)
                .activityBackgroundTint(Color.black.opacity(0.75))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let range = context.state.range
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.title, systemImage: "timer")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.isletoFocus)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: range, countsDown: true)
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 90)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        (Text("Termina às ") + Text(range.upperBound, style: .time))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ProgressView(timerInterval: range, countsDown: true) {
                            EmptyView()
                        } currentValueLabel: {
                            EmptyView()
                        }
                        .tint(Color.isletoFocus)
                    }
                }
            } compactLeading: {
                Image(systemName: "timer").foregroundStyle(Color.isletoFocus)
            } compactTrailing: {
                Text(timerInterval: range, countsDown: true)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 46)
            } minimal: {
                Image(systemName: "timer").foregroundStyle(Color.isletoFocus)
            }
        }
    }
}

private struct LockScreenTimerView: View {
    let title: String
    let range: ClosedRange<Date>

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: "timer")
                    .font(.headline)
                    .foregroundStyle(.white)
                ProgressView(timerInterval: range, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .tint(Color.isletoFocus)
            }
            Text(timerInterval: range, countsDown: true)
                .font(.title.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.trailing)
                .frame(width: 96)
        }
        .padding()
    }
}
