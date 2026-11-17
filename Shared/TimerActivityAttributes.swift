import ActivityKit
import Foundation

/// Live Activity data. Compiled into the app (which starts it) and the widget
/// extension (which draws it).
///
/// Only the start and end dates: the countdown is drawn by system timers, so it
/// stays correct with the app closed and without push notifications.
struct TimerActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var start: Date
        var end: Date

        var range: ClosedRange<Date> { start...max(start, end) }
    }

    var title: String
}
