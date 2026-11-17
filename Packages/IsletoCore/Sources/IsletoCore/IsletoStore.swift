import Foundation
import GRDB

/// Everything the "Today" screen and the widget show.
public struct DaySummary: Equatable, Sendable {
    public let waterMl: Int
    public let waterGoalMl: Int
    public let focusSessions: Int
    public let activeFocus: ActiveFocus?
    public let habits: [Habit]

    public init(waterMl: Int, waterGoalMl: Int, focusSessions: Int, activeFocus: ActiveFocus?, habits: [Habit]) {
        self.waterMl = waterMl
        self.waterGoalMl = waterGoalMl
        self.focusSessions = focusSessions
        self.activeFocus = activeFocus
        self.habits = habits
    }

    /// 0...1, for progress bars.
    public var waterProgress: Double {
        waterGoalMl > 0 ? min(Double(waterMl) / Double(waterGoalMl), 1) : 0
    }
}

/// Entry point used by the app and the widget.
public struct IsletoStore: Sendable {
    public let water: WaterStore
    public let focus: FocusStore
    public let habits: HabitStore
    private let database: DatabaseQueue

    public init(database: DatabaseQueue) {
        self.database = database
        water = WaterStore(database: database)
        focus = FocusStore(database: database)
        habits = HabitStore(database: database)
    }

    /// Today's data. A focus session that ended while the app was closed is saved
    /// first, so it is counted.
    public func today(now: Date = .now, calendar: Calendar = .current) throws -> DaySummary {
        try focus.settle(now: now, calendar: calendar)
        let day = LocalTime.day(now, calendar: calendar)
        return try database.read { db in
            DaySummary(
                waterMl: try WaterStore.total(db, day: day),
                waterGoalMl: WaterStore.goalMl,
                focusSessions: try FocusStore.sessions(db, day: day),
                activeFocus: try FocusStore.readActive(db),
                habits: try HabitStore.list(db, day: day)
            )
        }
    }

    public func schemaVersion() throws -> Int {
        try database.read { try Schema.version($0) }
    }
}
