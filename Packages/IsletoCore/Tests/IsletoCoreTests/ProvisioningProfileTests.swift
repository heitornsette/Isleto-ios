import Foundation
import XCTest
@testable import IsletoCore

final class ProvisioningProfileTests: XCTestCase {
    /// A real profile wraps the plist in binary CMS data; random bytes stand in for it.
    private func envelope(_ plist: String) -> Data {
        var data = Data([0x30, 0x82, 0x0F, 0x00, 0x06, 0x09, 0xFF, 0x00])
        data.append(Data(plist.utf8))
        data.append(Data([0x00, 0xA0, 0x82, 0x0B, 0xFF]))
        return data
    }

    private func plist(groups: [String]?) -> String {
        let groupsXML = groups.map { list in
            "<key>com.apple.security.application-groups</key><array>"
                + list.map { "<string>\($0)</string>" }.joined()
                + "</array>"
        } ?? ""
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>ExpirationDate</key><date>2026-11-24T12:00:00Z</date>
        <key>Entitlements</key><dict>
        <key>application-identifier</key><string>TEAM.app.isleto.ios</string>
        \(groupsXML)
        </dict></dict></plist>
        """
    }

    func testReadsGrantedGroupsAndExpiration() throws {
        let profile = try XCTUnwrap(ProvisioningProfile.parse(envelope(plist(groups: ["group.app.isleto.ios.TEAM"]))))
        XCTAssertEqual(profile.appGroups, ["group.app.isleto.ios.TEAM"])
        XCTAssertEqual(profile.expirationDate, Date(timeIntervalSince1970: 1_795_521_600))
    }

    func testNoGroupsWhenTheProfileGrantsNone() throws {
        let profile = try XCTUnwrap(ProvisioningProfile.parse(envelope(plist(groups: nil))))
        XCTAssertEqual(profile.appGroups, [])
    }

    func testNilForDataWithoutAPlist() {
        XCTAssertNil(ProvisioningProfile.parse(Data([0x01, 0x02, 0x03])))
        XCTAssertNil(ProvisioningProfile.parse(Data("<?xml version=\"1.0\"?> sem fim".utf8)))
    }

    func testNilWhenTheFileIsMissing() {
        let url = FileManager.default.temporaryDirectory.appending(path: "nao-existe-\(UUID().uuidString)")
        XCTAssertNil(ProvisioningProfile.load(bundleURL: url))
    }
}
