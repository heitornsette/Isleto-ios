import Foundation

/// Build a habit, or quit one. A quit habit's check marks a relapse.
public enum HabitKind: String, Sendable, CaseIterable {
    case build
    case quit
}

/// How a day is recorded.
public enum HabitRecord: String, Sendable, CaseIterable {
    /// Done or not done.
    case check
    /// A count toward a daily target (e.g. 8 glasses). Each tap adds one.
    case count
    /// A measure with a unit toward a daily target (e.g. 5 km).
    case measure
}

/// When the habit is due.
public enum HabitSchedule: Equatable, Sendable {
    case daily
    /// Weekdays, 1 = Monday ... 7 = Sunday.
    case weekdays(Set<Int>)
    /// Any days, this many per week (Monday to Sunday).
    case timesPerWeek(Int)

    /// Stored form: "daily", "weekdays:1,3,5" or "weekly:3". Unknown text is daily.
    public init(storage: String) {
        if storage.hasPrefix("weekdays:") {
            let days = Set(storage.dropFirst("weekdays:".count).split(separator: ",").compactMap { Int($0) }.filter { (1...7).contains($0) })
            self = days.isEmpty ? .daily : .weekdays(days)
        } else if storage.hasPrefix("weekly:"), let times = Int(storage.dropFirst("weekly:".count)) {
            self = .timesPerWeek(min(max(times, 1), 7))
        } else {
            self = .daily
        }
    }

    public var storage: String {
        switch self {
        case .daily: "daily"
        case .weekdays(let days): "weekdays:" + days.sorted().map(String.init).joined(separator: ",")
        case .timesPerWeek(let times): "weekly:\(times)"
        }
    }

    /// Whether the habit is due on `day`. "Times per week" can be done on any day.
    public func isDue(on day: Day) -> Bool {
        switch self {
        case .daily, .timesPerWeek: true
        case .weekdays(let days): days.contains(day.weekday)
        }
    }
}

/// A reminder time, local.
public struct ReminderTime: Hashable, Comparable, Sendable {
    public let hour: Int
    public let minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    public static func < (lhs: ReminderTime, rhs: ReminderTime) -> Bool {
        (lhs.hour, lhs.minute) < (rhs.hour, rhs.minute)
    }

    /// "HH:MM".
    public var text: String { String(format: "%02ld:%02ld", hour, minute) }

    /// Stored form: "HH:MM" times separated by commas.
    public static func list(storage: String) -> [ReminderTime] {
        storage.split(separator: ",").compactMap { part in
            let pieces = part.split(separator: ":").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            return pieces.count == 2 ? ReminderTime(hour: pieces[0], minute: pieces[1]) : nil
        }
    }

    public static func storage(_ times: [ReminderTime]) -> String {
        times.map(\.text).joined(separator: ",")
    }
}

/// Everything the user edits in the habit form.
public struct HabitDefinition: Equatable, Sendable {
    public static let maxNameLength = 24
    public static let maxReminders = 3

    public var name: String
    public var description: String
    /// SF Symbol name.
    public var icon: String
    /// "#RRGGBB".
    public var color: String
    public var kind: HabitKind
    public var schedule: HabitSchedule
    public var record: HabitRecord
    /// Daily target for count and measure. 1 for check.
    public var target: Double
    /// Unit of a measure, e.g. "km".
    public var unit: String
    public var reminders: [ReminderTime]
    public var categoryIDs: Set<Int64>

    public init(
        name: String = "",
        description: String = "",
        icon: String = "checkmark",
        color: String = "#3AA76D",
        kind: HabitKind = .build,
        schedule: HabitSchedule = .daily,
        record: HabitRecord = .check,
        target: Double = 1,
        unit: String = "",
        reminders: [ReminderTime] = [],
        categoryIDs: Set<Int64> = []
    ) {
        self.name = name
        self.description = description
        self.icon = icon
        self.color = color
        self.kind = kind
        self.schedule = schedule
        self.record = record
        self.target = target
        self.unit = unit
        self.reminders = reminders
        self.categoryIDs = categoryIDs
    }

    /// The definition as it is saved, or nil if the name is empty.
    /// A quit habit is always recorded as a check (the relapse); a count target is a
    /// whole number of at least 1; reminders are unique, sorted and at most three.
    public func normalized() -> HabitDefinition? {
        var result = self
        result.name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxNameLength))
        guard !result.name.isEmpty else { return nil }
        result.description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        result.unit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.icon.isEmpty { result.icon = "checkmark" }
        if kind == .quit { result.record = .check }
        switch result.record {
        case .check:
            result.target = 1
            result.unit = ""
        case .count:
            result.target = max(1, target.rounded())
            result.unit = ""
        case .measure:
            result.target = target > 0 ? target : 1
        }
        if case .timesPerWeek(let times) = schedule {
            result.schedule = .timesPerWeek(min(max(times, 1), 7))
        }
        result.reminders = Array(Set(reminders).sorted().prefix(Self.maxReminders))
        return result
    }
}

public struct HabitCategory: Equatable, Hashable, Sendable, Identifiable {
    public let id: Int64
    public let name: String

    public init(id: Int64, name: String) {
        self.id = id
        self.name = name
    }
}
