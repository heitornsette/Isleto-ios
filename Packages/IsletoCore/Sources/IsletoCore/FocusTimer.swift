import Foundation

/// Time range of a timer, for the Live Activity.
///
/// A free Apple ID has no push notifications, so a Live Activity cannot be updated
/// from outside. It only stays correct on its own through system timers
/// (`Text(timerInterval:)`, `ProgressView(timerInterval:)`), which need this range.
public enum FocusTimer {
    public static let minimumMinutes = 1
    public static let maximumMinutes = 8 * 60 // the system ends a Live Activity after 8 hours

    public static func interval(startingAt start: Date, minutes: Int) -> ClosedRange<Date> {
        let clamped = min(max(minutes, minimumMinutes), maximumMinutes)
        return start...start.addingTimeInterval(TimeInterval(clamped * 60))
    }
}
