import Foundation

/// What the signature really granted, read from the `embedded.mobileprovision` that
/// the signing tool (Sideloadly, AltStore, Xcode) puts inside each signed bundle.
///
/// The file is a CMS-signed envelope around an XML property list. The signature is
/// not checked here: this is for diagnostics only, the system enforces the real rules.
public struct ProvisioningProfile: Equatable, Sendable {
    public static let fileName = "embedded.mobileprovision"

    /// `com.apple.security.application-groups` granted by the profile.
    public let appGroups: [String]
    public let expirationDate: Date?

    public init(appGroups: [String], expirationDate: Date?) {
        self.appGroups = appGroups
        self.expirationDate = expirationDate
    }

    public static func parse(_ data: Data) -> ProvisioningProfile? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex)
        else {
            return nil
        }
        let xml = data.subdata(in: start.lowerBound..<end.upperBound)
        guard let plist = try? PropertyListSerialization.propertyList(from: xml, format: nil) as? [String: Any] else {
            return nil
        }
        let entitlements = plist["Entitlements"] as? [String: Any] ?? [:]
        return ProvisioningProfile(
            appGroups: entitlements["com.apple.security.application-groups"] as? [String] ?? [],
            expirationDate: plist["ExpirationDate"] as? Date
        )
    }

    /// nil when the file is missing (unsigned or simulator build) or unreadable.
    public static func load(bundleURL: URL) -> ProvisioningProfile? {
        guard let data = try? Data(contentsOf: bundleURL.appending(path: fileName)) else {
            return nil
        }
        return parse(data)
    }
}
