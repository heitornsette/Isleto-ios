import Foundation

/// A streak, in days, or in weeks for "times per week" habits.
public struct Streak: Equatable, Sendable {
    public enum Unit: Sendable {
        case days
        case weeks
    }

    public let value: Int
    public let unit: Unit

    public init(_ value: Int, _ unit: Unit = .days) {
        self.value = value
        self.unit = unit
    }
}

/// A habit with its recent history, ready to show.
public struct Habit: Equatable, Sendable, Identifiable {
    public let id: Int64
    public let definition: HabitDefinition
    public let archived: Bool
    public let sortOrder: Int
    /// Day the habit was created.
    public let created: Day
    /// "Today" when this was loaded.
    public let today: Day
    /// Value of each day (by `Day.number`) in the loaded window: 1 for a check
    /// (or a relapse), the count or the measure otherwise.
    public let values: [Int: Double]
    public let streak: Streak

    public init(
        id: Int64,
        definition: HabitDefinition,
        archived: Bool = false,
        sortOrder: Int = 0,
        created: Day,
        today: Day,
        values: [Int: Double]
    ) {
        self.id = id
        self.definition = definition
        self.archived = archived
        self.sortOrder = sortOrder
        self.created = created
        self.today = today
        self.values = values
        streak = HabitRules.streak(
            definition: definition,
            values: values,
            created: created,
            today: today
        )
    }

    public var name: String { definition.name }

    public func value(on day: Day) -> Double { values[day.number] ?? 0 }

    public var todayValue: Double { value(on: today) }

    /// For a quit habit: a relapse was marked on `day`.
    public func relapsed(on day: Day) -> Bool {
        definition.kind == .quit && value(on: day) > 0
    }

    /// Whether the square of `day` is filled: target reached for a build habit,
    /// a clean day (since creation, up to today) for a quit habit.
    public func isComplete(_ day: Day) -> Bool {
        HabitRules.isComplete(definition: definition, value: values[day.number], day: day, created: created, today: today)
    }

    /// 0...1 progress of today, for the ring of count and measure habits.
    public var progressToday: Double {
        guard definition.target > 0 else { return 0 }
        return min(todayValue / definition.target, 1)
    }

    /// "Done" state of the card's button: target reached today, or for a quit
    /// habit, no relapse today.
    public var doneToday: Bool {
        definition.kind == .quit ? !relapsed(on: today) : isComplete(today)
    }

    /// Checks done in the week of `day` (Monday to Sunday), for "times per week".
    public func completedDays(inWeekOf day: Day) -> Int {
        let start = day.startOfWeek
        return (0..<7).filter { isComplete(start.adding($0)) }.count
    }
}

/// Completion and streak rules.
public enum HabitRules {
    public static func isComplete(
        definition: HabitDefinition,
        value: Double?,
        day: Day,
        created: Day,
        today: Day
    ) -> Bool {
        switch definition.kind {
        case .build:
            guard let value else { return false }
            return value >= max(definition.target, .leastNonzeroMagnitude)
        case .quit:
            return day >= created && day <= today && (value ?? 0) <= 0
        }
    }

    /// - Build, daily: consecutive days done. While today is not done yet, the
    ///   streak up to yesterday still stands (the desktop rule).
    /// - Build, weekdays: consecutive due days done; days not due are skipped.
    /// - Build, times per week: consecutive weeks that reached the count; the
    ///   current week only counts once it is reached.
    /// - Quit: days since the last relapse (0 if it was today), or since creation.
    public static func streak(definition: HabitDefinition, values: [Int: Double], created: Day, today: Day) -> Streak {
        func done(_ day: Day) -> Bool {
            isComplete(definition: definition, value: values[day.number], day: day, created: created, today: today)
        }
        let oldest = max(created, today.adding(-HabitStore.historyDays))

        switch (definition.kind, definition.schedule) {
        case (.quit, _):
            let relapses = values.filter { $0.value > 0 && $0.key <= today.number }.keys
            if let last = relapses.max() {
                return Streak(today.number - last)
            }
            return Streak(max(0, today.number - created.number + 1))

        case (.build, .daily):
            let days = values.keys.filter { done(Day(number: $0)) }.sorted(by: >)
            return Streak(HabitStreak.streak(daysNewestFirst: days, today: today.number))

        case (.build, .weekdays):
            var day = today
            if definition.schedule.isDue(on: today), !done(today) {
                day = today.adding(-1)
            }
            var count = 0
            while day >= oldest {
                if definition.schedule.isDue(on: day) {
                    guard done(day) else { break }
                    count += 1
                }
                day = day.adding(-1)
            }
            return Streak(count)

        case (.build, .timesPerWeek(let times)):
            func reached(_ weekStart: Day) -> Bool {
                (0..<7).filter { done(weekStart.adding($0)) }.count >= times
            }
            var week = today.startOfWeek
            var count = 0
            if reached(week) {
                count = 1
            }
            week = week.adding(-7)
            while week.adding(6) >= oldest, reached(week) {
                count += 1
                week = week.adding(-7)
            }
            return Streak(count, .weeks)
        }
    }
}
