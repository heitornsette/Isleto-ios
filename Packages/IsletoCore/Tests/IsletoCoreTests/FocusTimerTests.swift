import Foundation
import XCTest
@testable import IsletoCore

final class FocusTimerTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    func testIntervalLastsTheGivenMinutes() {
        let range = FocusTimer.interval(startingAt: start, minutes: 25)
        XCTAssertEqual(range.lowerBound, start)
        XCTAssertEqual(range.upperBound.timeIntervalSince(start), 25 * 60)
    }

    func testIntervalIsClampedToWhatALiveActivityCanShow() {
        XCTAssertEqual(FocusTimer.interval(startingAt: start, minutes: 0).upperBound.timeIntervalSince(start), 60)
        XCTAssertEqual(FocusTimer.interval(startingAt: start, minutes: -5).upperBound.timeIntervalSince(start), 60)
        XCTAssertEqual(FocusTimer.interval(startingAt: start, minutes: 10_000).upperBound.timeIntervalSince(start), 8 * 3600)
    }
}
