import Foundation
import GRDB
import XCTest
@testable import IsletoCore

final class FocusStoreTests: XCTestCase {
    private let calendar = TestTime.calendar
    private let nine = TestTime.date(2026, 11, 17, 9)

    func testStartSavesARunningSessionOf25Minutes() throws {
        let focus = FocusStore(database: try IsletoDatabase.inMemory())
        let session = try focus.start(now: nine, calendar: calendar)
        XCTAssertEqual(session.start, nine)
        XCTAssertEqual(session.end.timeIntervalSince(nine), 25 * 60)
        XCTAssertEqual(session.minutes, 25)
        XCTAssertEqual(try focus.active(), session)
    }

    func testStartingAgainKeepsTheRunningSession() throws {
        let focus = FocusStore(database: try IsletoDatabase.inMemory())
        let first = try focus.start(now: nine, calendar: calendar)
        let second = try focus.start(now: nine.addingTimeInterval(60), calendar: calendar)
        XCTAssertEqual(first, second)
    }

    func testSettleSavesOnlyAFinishedSessionOnce() throws {
        let db = try IsletoDatabase.inMemory()
        let focus = FocusStore(database: db)
        try focus.start(now: nine, calendar: calendar)

        XCTAssertNil(try focus.settle(now: nine.addingTimeInterval(24 * 60), calendar: calendar))
        XCTAssertEqual(try focus.sessions(on: nine, calendar: calendar), 0)

        let end = nine.addingTimeInterval(25 * 60)
        XCTAssertNotNil(try focus.settle(now: end.addingTimeInterval(3600), calendar: calendar))
        XCTAssertNil(try focus.settle(now: end.addingTimeInterval(7200), calendar: calendar))
        XCTAssertNil(try focus.active())
        XCTAssertEqual(try focus.sessions(on: nine, calendar: calendar), 1)

        // Saved like the desktop: the end time, local, and the minutes.
        let row = try db.read { try Row.fetchOne($0, sql: "SELECT finished_at, minutes FROM focus_sessions") }
        XCTAssertEqual(row?["finished_at"] as String?, "2026-11-17 09:25:00")
        XCTAssertEqual(row?["minutes"] as Int?, 25)
    }

    func testCancelDropsTheSessionWithoutSavingIt() throws {
        let focus = FocusStore(database: try IsletoDatabase.inMemory())
        try focus.start(now: nine, calendar: calendar)
        try focus.cancel()
        XCTAssertNil(try focus.active())
        XCTAssertNil(try focus.settle(now: nine.addingTimeInterval(3600), calendar: calendar))
        XCTAssertEqual(try focus.sessions(on: nine, calendar: calendar), 0)
    }

    func testStartingAfterAFinishedSessionSavesItAndStartsANewOne() throws {
        let focus = FocusStore(database: try IsletoDatabase.inMemory())
        try focus.start(now: nine, calendar: calendar)
        let later = nine.addingTimeInterval(40 * 60)
        let next = try focus.start(now: later, calendar: calendar)
        XCTAssertEqual(next.start, later)
        XCTAssertEqual(try focus.sessions(on: nine, calendar: calendar), 1)
    }

    /// Same idea as the desktop test `counts_only_todays_focus_sessions`.
    func testCountsOnlyTheDaysSessions() throws {
        let focus = FocusStore(database: try IsletoDatabase.inMemory())
        let yesterday = TestTime.date(2026, 11, 16, 9)
        try focus.start(now: yesterday, calendar: calendar)
        try focus.settle(now: yesterday.addingTimeInterval(3600), calendar: calendar)
        try focus.start(now: nine, calendar: calendar)
        try focus.settle(now: nine.addingTimeInterval(3600), calendar: calendar)
        XCTAssertEqual(try focus.sessions(on: nine, calendar: calendar), 1)
    }
}
