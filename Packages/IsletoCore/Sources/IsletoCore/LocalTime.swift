import Foundation

/// Dates as the desktop stores them: local time, as text.
/// `day` matches SQLite's `date('now', 'localtime')` and `timestamp` its
/// `datetime('now', 'localtime')`, so rows written here and on the desktop compare equal.
public enum LocalTime {
    /// "YYYY-MM-DD".
    public static func day(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04ld-%02ld-%02ld", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// "YYYY-MM-DD HH:MM:SS".
    public static func timestamp(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "%04ld-%02ld-%02ld %02ld:%02ld:%02ld",
            c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0
        )
    }

    /// Midnight that starts the next day, when "today" totals reset.
    public static func startOfNextDay(after date: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
    }
}
