import Foundation

/// Habit streak rules, ported from the desktop (`isleto/src/db.rs`).
public enum HabitStreak {
    /// Days since 1970-01-01 for a "YYYY-MM-DD" date (the format of `habit_checks.day`).
    public static func dayNumber(_ date: String) -> Int? {
        let parts = date.split(separator: "-", omittingEmptySubsequences: false).map { Int($0) }
        guard parts.count >= 3, let year = parts[0], let month = parts[1], let day = parts[2] else {
            return nil
        }
        // Civil-from-days algorithm (Howard Hinnant), valid for the proleptic Gregorian calendar.
        let y = month <= 2 ? year - 1 : year
        let era = floorDivide(y, 400)
        let yearOfEra = y - era * 400
        let dayOfYear = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    /// "YYYY-MM-DD" of `date` in `calendar`'s time zone, like SQLite's `date('now', 'localtime')`.
    public static func dayString(for date: Date, calendar: Calendar = .current) -> String {
        LocalTime.day(date, calendar: calendar)
    }

    /// Consecutive days with a check, newest first. Counts from today, or from yesterday
    /// while today is not checked yet, so the streak is not lost before the day is over.
    public static func streak(daysNewestFirst days: [Int], today: Int) -> Int {
        guard let first = days.first, first == today || first == today - 1 else {
            return 0
        }
        var expected = first
        var count = 0
        for day in days {
            if day == expected {
                count += 1
                expected -= 1
            } else if day < expected {
                break
            }
        }
        return count
    }

    /// Floor division for a positive divisor (Rust's `div_euclid`).
    private static func floorDivide(_ a: Int, _ b: Int) -> Int {
        a >= 0 ? a / b : (a - b + 1) / b
    }
}
