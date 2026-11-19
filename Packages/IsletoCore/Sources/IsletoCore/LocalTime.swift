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

    /// Reads "YYYY-MM-DD HH:MM:SS" back (or "YYYY-MM-DD", as midnight). Nil if malformed.
    public static func date(_ text: String, calendar: Calendar = .current) -> Date? {
        let parts = text.split(whereSeparator: { $0 == "-" || $0 == " " || $0 == ":" || $0 == "T" }).map { Int($0) }
        guard parts.count == 3 || parts.count == 6, parts.allSatisfy({ $0 != nil }) else { return nil }
        let values = parts.map { $0! }
        var components = DateComponents(year: values[0], month: values[1], day: values[2])
        if values.count == 6 {
            components.hour = values[3]
            components.minute = values[4]
            components.second = values[5]
        }
        return calendar.date(from: components)
    }

    /// Midnight that starts the next day, when "today" totals reset.
    public static func startOfNextDay(after date: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
    }
}
