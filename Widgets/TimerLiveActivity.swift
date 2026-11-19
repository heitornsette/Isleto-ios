import ActivityKit
import SwiftUI
import WidgetKit

/// Live Activity of the focus session or of the rest between workout sets, on the lock
/// screen and in the Dynamic Island.
///
/// Only system timers (`Text(timerInterval:)`, `ProgressView(timerInterval:)`):
/// they keep counting with the app closed. A free Apple ID has no push, so nothing
/// else could update this view.
struct TimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerActivityAttributes.self) { context in
            LockScreenTimerView(title: context.attributes.title, kind: context.attributes.kind, range: context.state.range)
                .activityBackgroundTint(Color.black.opacity(0.75))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let range = context.state.range
            let kind = context.attributes.kind
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.title, systemImage: kind.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(kind.color)
                        .lineLimit(1)
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
                        .tint(kind.color)
                    }
                }
            } compactLeading: {
                Image(systemName: kind.symbol).foregroundStyle(kind.color)
            } compactTrailing: {
                Text(timerInterval: range, countsDown: true)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 46)
            } minimal: {
                Image(systemName: kind.symbol).foregroundStyle(kind.color)
            }
        }
    }
}

extension TimerActivityAttributes.Kind {
    var symbol: String {
        switch self {
        case .focus: "timer"
        case .rest: "dumbbell.fill"
        }
    }

    var color: Color {
        switch self {
        case .focus: .isletoFocus
        case .rest: .isletoMint
        }
    }
}

private struct LockScreenTimerView: View {
    let title: String
    let kind: TimerActivityAttributes.Kind
    let range: ClosedRange<Date>

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: kind.symbol)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                ProgressView(timerInterval: range, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .tint(kind.color)
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
