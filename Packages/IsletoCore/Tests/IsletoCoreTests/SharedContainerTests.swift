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

    private let info: [String: Any] = ["IsletoAppGroup": "group.app.isleto.ios"]

    func testUsesTheGroupRenamedBySigning() {
        // iloader with a free Apple ID: "<group>.<TEAM ID>", no ALTAppGroups key.
        let granted = ["group.app.isleto.ios.TEAM123"]
        XCTAssertEqual(SharedContainer.groupID(infoDictionary: info, grantedGroups: granted), "group.app.isleto.ios.TEAM123")
        let status = SharedContainer.resolve(infoDictionary: info, grantedGroups: granted) { id in
            id == "group.app.isleto.ios.TEAM123" ? self.url : nil
        }
        XCTAssertEqual(status, .ready(groupID: "group.app.isleto.ios.TEAM123", url: url))
    }

    func testPrefersTheConfiguredGroupWhenGrantedUnchanged() {
        let granted = ["group.app.isleto.ios.TEAM123", "group.app.isleto.ios"]
        XCTAssertEqual(SharedContainer.groupID(infoDictionary: info, grantedGroups: granted), "group.app.isleto.ios")
    }

    func testIgnoresUnrelatedGrantedGroups() {
        // Same prefix without the dot is another group, not a renamed one.
        let granted = ["group.app.isleto.iosx", "group.other"]
        XCTAssertEqual(SharedContainer.groupID(infoDictionary: info, grantedGroups: granted), "group.app.isleto.ios")
        XCTAssertEqual(
            SharedContainer.resolve(infoDictionary: info, grantedGroups: granted) { _ in nil },
            .unavailable(groupID: "group.app.isleto.ios")
        )
    }

    func testNoGrantedGroupsKeepsTheConfiguredOne() {
        // Sideloadly with a free Apple ID granted nothing: report the configured group as unavailable.
        XCTAssertEqual(SharedContainer.groupID(infoDictionary: info, grantedGroups: []), "group.app.isleto.ios")
        // No profile at all (simulator): keep the configured group.
        XCTAssertEqual(SharedContainer.groupID(infoDictionary: info, grantedGroups: nil), "group.app.isleto.ios")
    }

    func testAltStoreKeyWinsOverTheProfile() {
        var withAlt = info
        withAlt["ALTAppGroups"] = ["group.app.isleto.ios.ALT"]
        XCTAssertEqual(
            SharedContainer.groupID(infoDictionary: withAlt, grantedGroups: ["group.app.isleto.ios.TEAM123"]),
            "group.app.isleto.ios.ALT"
        )
    }

    func testPrefersTheGroupRewrittenByAltStore() {
        let info: [String: Any] = ["IsletoAppGroup": "group.a", "ALTAppGroups": ["group.a.TEAMID"]]
        XCTAssertEqual(SharedContainer.groupID(infoDictionary: info), "group.a.TEAMID")
    }
}
