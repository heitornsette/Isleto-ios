import Foundation
import XCTest
@testable import IsletoCore

/// Same cases as the desktop tests (`isleto/src/db.rs`).
final class HabitStreakTests: XCTestCase {
    func testDayNumbersCountDaysCorrectly() throws {
        XCTAssertEqual(HabitStreak.dayNumber("1970-01-01"), 0)
        XCTAssertEqual(HabitStreak.dayNumber("1970-01-02"), 1)
        let leap = try XCTUnwrap(HabitStreak.dayNumber("2000-03-01")) - XCTUnwrap(HabitStreak.dayNumber("2000-02-28"))
        XCTAssertEqual(leap, 2)
        let newYear = try XCTUnwrap(HabitStreak.dayNumber("2026-01-01")) - XCTUnwrap(HabitStreak.dayNumber("2025-12-31"))
        XCTAssertEqual(newYear, 1)
        XCTAssertEqual(HabitStreak.dayNumber("1969-12-31"), -1)
        XCTAssertNil(HabitStreak.dayNumber("nope"))
    }

    func testStreakCountsConsecutiveDaysAndKeepsYesterdays() {
        XCTAssertEqual(HabitStreak.streak(daysNewestFirst: [], today: 100), 0)
        XCTAssertEqual(HabitStreak.streak(daysNewestFirst: [100, 99, 98], today: 100), 3)
        // Today not checked yet: the streak from yesterday still stands.
        XCTAssertEqual(HabitStreak.streak(daysNewestFirst: [99, 98], today: 100), 2)
        // A gap breaks it.
        XCTAssertEqual(HabitStreak.streak(daysNewestFirst: [100, 99, 97, 96], today: 100), 2)
        // Last check two days ago: lost.
        XCTAssertEqual(HabitStreak.streak(daysNewestFirst: [98, 97], today: 100), 0)
    }

    func testDayStringUsesTheCalendarTimeZone() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Sao_Paulo"))
        // 2026-03-01 02:00 UTC is still 2026-02-28 in São Paulo (UTC-3).
        let date = Date(timeIntervalSince1970: 1_772_330_400)
        XCTAssertEqual(HabitStreak.dayString(for: date, calendar: calendar), "2026-02-28")
    }
}
