import Foundation
import GRDB
import XCTest
@testable import IsletoCore

final class WaterStoreTests: TemporaryDirectoryTestCase {
    private let calendar = TestTime.calendar
    private let today = TestTime.date(2026, 11, 17, 10)
    private let yesterday = TestTime.date(2026, 11, 16, 23, 50)

    /// Same case as the desktop test `water_sums_today_and_undo_removes_the_last_entry`.
    func testSumsTodayAndUndoRemovesTheLastEntryOfToday() throws {
        let water = WaterStore(database: try IsletoDatabase.inMemory())
        XCTAssertEqual(try water.total(on: today, calendar: calendar), 0)
        XCTAssertFalse(try water.undoLast(on: today, calendar: calendar))

        try water.add(ml: 250, at: today, calendar: calendar)
        try water.add(ml: 500, at: today, calendar: calendar)
        // Yesterday's water must neither count nor be undone.
        try water.add(ml: 999, at: yesterday, calendar: calendar)
        XCTAssertEqual(try water.total(on: today, calendar: calendar), 750)

        XCTAssertTrue(try water.undoLast(on: today, calendar: calendar))
        XCTAssertEqual(try water.total(on: today, calendar: calendar), 250)
        XCTAssertTrue(try water.undoLast(on: today, calendar: calendar))
        XCTAssertFalse(try water.undoLast(on: today, calendar: calendar))
        XCTAssertEqual(try water.total(on: yesterday, calendar: calendar), 999)
    }

    func testDefaultsMatchTheDesktopConfig() {
        XCTAssertEqual(WaterStore.goalMl, 2000)
        XCTAssertEqual(WaterStore.glassMl, 250)
    }

    func testStoresLocalTimeLikeTheDesktop() throws {
        let db = try IsletoDatabase.inMemory()
        try WaterStore(database: db).add(at: TestTime.date(2026, 1, 2, 3, 4), calendar: calendar)
        let row = try db.read { try Row.fetchOne($0, sql: "SELECT logged_at, ml FROM water_logs") }
        XCTAssertEqual(row?["logged_at"] as String?, "2026-01-02 03:04:00")
        XCTAssertEqual(row?["ml"] as Int?, 250)
    }

    /// Two connections to one file stand in for the app and the widget extension:
    /// concurrent writes must not be lost.
    func testConcurrentAddsFromTwoConnectionsAreNotLost() throws {
        let url = directory.appending(path: IsletoDatabase.fileName)
        let app = WaterStore(database: try IsletoDatabase.open(at: url))
        let widget = WaterStore(database: try IsletoDatabase.open(at: url))
        let perConnection = 40
        let day = today
        let calendar = calendar

        DispatchQueue.concurrentPerform(iterations: 2) { index in
            let store = index == 0 ? app : widget
            for _ in 0..<perConnection {
                try? store.add(ml: 1, at: day, calendar: calendar)
            }
        }

        XCTAssertEqual(try app.total(on: today, calendar: calendar), 2 * perConnection)
    }
}
