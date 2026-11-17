import Foundation
import XCTest
@testable import IsletoCore

final class SharedContainerTests: XCTestCase {
    private let url = URL(filePath: "/tmp/group")

    func testReadyWhenTheSystemGivesAContainer() {
        let status = SharedContainer.resolve(infoDictionary: ["IsletoAppGroup": "group.a"]) { _ in self.url }
        XCTAssertEqual(status, .ready(groupID: "group.a", url: url))
    }

    func testUnavailableWhenTheSignatureDidNotGrantTheGroup() {
        let status = SharedContainer.resolve(infoDictionary: ["IsletoAppGroup": "group.a"]) { _ in nil }
        XCTAssertEqual(status, .unavailable(groupID: "group.a"))
    }

    func testMissingWhenTheInfoPlistHasNoGroup() {
        XCTAssertEqual(SharedContainer.resolve(infoDictionary: [:]) { _ in self.url }, .missingGroupID)
        XCTAssertEqual(SharedContainer.resolve(infoDictionary: nil) { _ in self.url }, .missingGroupID)
        XCTAssertEqual(SharedContainer.resolve(infoDictionary: ["IsletoAppGroup": ""]) { _ in self.url }, .missingGroupID)
    }

    func testPrefersTheGroupRewrittenByAltStore() {
        let info: [String: Any] = ["IsletoAppGroup": "group.a", "ALTAppGroups": ["group.a.TEAMID"]]
        XCTAssertEqual(SharedContainer.groupID(infoDictionary: info), "group.a.TEAMID")
    }
}
