import Foundation
import XCTest
@testable import IsletoCore

final class IsletoStoreTests: XCTestCase {
    private let calendar = TestTime.calendar
    private let nine = TestTime.date(2026, 11, 17, 9)

    func testTodaySummarizesTheDay() throws {
        let store = IsletoStore(database: try IsletoDatabase.inMemory())
        try store.water.add(at: nine, calendar: calendar)
        try store.water.add(at: nine, calendar: calendar)
        try store.habits.create(HabitDefinition(name: "Ler"), at: nine, calendar: calendar)

        let summary = try store.today(now: nine, calendar: calendar)
        XCTAssertEqual(summary.waterMl, 500)
        XCTAssertEqual(summary.waterGoalMl, 2000)
        XCTAssertEqual(summary.waterProgress, 0.25, accuracy: 0.0001)
        XCTAssertEqual(summary.focusSessions, 0)
        XCTAssertNil(summary.activeFocus)
        XCTAssertEqual(summary.habits.map(\.name), ["Ler"])
    }

    /// The app may be closed when a focus session ends: reading the day counts it.
    func testTodayCountsAFocusSessionThatEndedWhileClosed() throws {
        let store = IsletoStore(database: try IsletoDatabase.inMemory())
        try store.focus.start(now: nine, calendar: calendar)
        XCTAssertNotNil(try store.today(now: nine.addingTimeInterval(60), calendar: calendar).activeFocus)

        let after = try store.today(now: nine.addingTimeInterval(30 * 60), calendar: calendar)
        XCTAssertNil(after.activeFocus)
        XCTAssertEqual(after.focusSessions, 1)
    }

    func testWaterProgressIsCappedAtTheGoal() {
        let summary = DaySummary(waterMl: 3000, waterGoalMl: 2000, focusSessions: 0, activeFocus: nil, habits: [])
        XCTAssertEqual(summary.waterProgress, 1)
    }

    func testLocalTimeFormatsLikeSQLite() {
        let date = TestTime.date(2026, 3, 4, 5, 6)
        XCTAssertEqual(LocalTime.day(date, calendar: calendar), "2026-03-04")
        XCTAssertEqual(LocalTime.timestamp(date, calendar: calendar), "2026-03-04 05:06:00")
        XCTAssertEqual(LocalTime.startOfNextDay(after: date, calendar: calendar), TestTime.date(2026, 3, 5, 0, 0))
    }
}
