import Foundation

/// A calendar day, as stored in `habit_checks.day` ("YYYY-MM-DD", local time).
/// `number` counts days since 1970-01-01, so day arithmetic is plain integer math.
public struct Day: Hashable, Comparable, Sendable {
    public let number: Int

    public init(number: Int) {
        self.number = number
    }

    public init?(_ string: String) {
        guard let number = HabitStreak.dayNumber(string) else { return nil }
        self.number = number
    }

    /// The local day of `date`.
    public init(_ date: Date, calendar: Calendar = .current) {
        number = HabitStreak.dayNumber(LocalTime.day(date, calendar: calendar)) ?? 0
    }

    public static func < (lhs: Day, rhs: Day) -> Bool { lhs.number < rhs.number }

    public func adding(_ days: Int) -> Day { Day(number: number + days) }

    /// 1 = Monday ... 7 = Sunday (1970-01-01 was a Thursday).
    public var weekday: Int {
        ((number % 7 + 7) % 7 + 3) % 7 + 1
    }

    /// The Monday of this day's week.
    public var startOfWeek: Day { adding(1 - weekday) }

    /// Year, month (1...12) and day of month. Inverse of `HabitStreak.dayNumber`
    /// (Howard Hinnant's civil-from-days).
    public var components: (year: Int, month: Int, day: Int) {
        let z = number + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let dayOfEra = z - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let mp = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * mp + 2) / 5 + 1
        let month = mp < 10 ? mp + 3 : mp - 9
        let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
        return (year, month, day)
    }

    /// "YYYY-MM-DD".
    public var string: String {
        let c = components
        return String(format: "%04ld-%02ld-%02ld", c.year, c.month, c.day)
    }

    /// Noon of this day in `calendar`, for display with date formatters.
    public func date(calendar: Calendar = .current) -> Date {
        let c = components
        return calendar.date(from: DateComponents(year: c.year, month: c.month, day: c.day, hour: 12)) ?? .distantPast
    }
}
