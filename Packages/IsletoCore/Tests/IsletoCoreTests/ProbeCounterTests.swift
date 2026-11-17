import Foundation
import XCTest
@testable import IsletoCore

final class ProbeCounterTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "IsletoCoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var databaseURL: URL { directory.appending(path: IsletoDatabase.fileName) }

    func testStartsAtZeroIncrementsAndResets() throws {
        let counter = ProbeCounter(database: try IsletoDatabase.inMemory())
        XCTAssertEqual(try counter.value(), 0)
        XCTAssertEqual(try counter.increment(), 1)
        XCTAssertEqual(try counter.increment(), 2)
        XCTAssertEqual(try counter.value(), 2)
        try counter.reset()
        XCTAssertEqual(try counter.value(), 0)
    }

    func testValueSurvivesReopeningTheFile() throws {
        do {
            let counter = ProbeCounter(database: try IsletoDatabase.open(at: databaseURL))
            try counter.increment()
            try counter.increment()
        }
        let reopened = ProbeCounter(database: try IsletoDatabase.open(at: databaseURL))
        XCTAssertEqual(try reopened.value(), 2)
    }

    /// Two connections to one file stand in for the app and the widget extension:
    /// concurrent increments must not be lost.
    func testConcurrentIncrementsFromTwoConnectionsAreNotLost() throws {
        let app = ProbeCounter(database: try IsletoDatabase.open(at: databaseURL))
        let widget = ProbeCounter(database: try IsletoDatabase.open(at: databaseURL))
        let perConnection = 50

        DispatchQueue.concurrentPerform(iterations: 2) { index in
            let counter = index == 0 ? app : widget
            for _ in 0..<perConnection {
                _ = try? counter.increment()
            }
        }

        XCTAssertEqual(try app.value(), 2 * perConnection)
    }

    func testCounterLivesInTheDesktopSettingsTable() throws {
        let db = try IsletoDatabase.inMemory()
        try ProbeCounter(database: db).increment()
        let stored = try db.read {
            try String.fetchOne($0, sql: "SELECT value FROM settings WHERE key = ?", arguments: [ProbeCounter.key])
        }
        XCTAssertEqual(stored, "1")
    }
}
