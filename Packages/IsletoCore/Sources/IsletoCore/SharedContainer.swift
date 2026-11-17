import Foundation

/// Locates the App Group container shared by the app and the widget extension.
///
/// With a free Apple ID, signing tools (iloader, SideStore, AltStore) rename the App
/// Group by appending the team ID, e.g. `group.app.isleto.ios.ABCDE12345`, so the
/// identifier in the Info.plist is not the one the signature granted. The real one is
/// taken from what the signing tool says, never guessed. No fallback container: if
/// nothing was granted, the app must say so.
public enum SharedContainer {
    /// Info.plist key with the App Group identifier (set from project.yml).
    public static let infoPlistKey = "IsletoAppGroup"
    /// Key that AltStore/SideStore add when they rewrite App Group identifiers at signing.
    public static let altStoreKey = "ALTAppGroups"

    public enum Status: Equatable, Sendable {
        /// Container found.
        case ready(groupID: String, url: URL)
        /// The Info.plist has no App Group identifier: build problem.
        case missingGroupID
        /// The system gave no container for this identifier: the signature did not grant it.
        case unavailable(groupID: String)
    }

    /// The App Group identifier to use, in this order:
    /// 1. the one written by AltStore/SideStore in `ALTAppGroups`;
    /// 2. the configured one, if the signature granted it unchanged (paid account, Xcode);
    /// 3. the granted one that is the configured one plus a suffix (renamed by the signer);
    /// 4. the configured one, which will then show as unavailable.
    ///
    /// - Parameter grantedGroups: App Groups of the embedded provisioning profile,
    ///   nil when there is no profile (simulator, unsigned build).
    public static func groupID(infoDictionary: [String: Any]?, grantedGroups: [String]? = nil) -> String? {
        if let rewritten = infoDictionary?[altStoreKey] as? [String], let first = rewritten.first, !first.isEmpty {
            return first
        }
        guard let configured = infoDictionary?[infoPlistKey] as? String, !configured.isEmpty else {
            return nil
        }
        guard let granted = grantedGroups else {
            return configured
        }
        if granted.contains(configured) {
            return configured
        }
        if let renamed = granted.sorted().first(where: { $0.hasPrefix(configured + ".") }) {
            return renamed
        }
        return configured
    }

    public static func resolve(
        infoDictionary: [String: Any]?,
        grantedGroups: [String]? = nil,
        containerURL: (String) -> URL? = { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
    ) -> Status {
        guard let id = groupID(infoDictionary: infoDictionary, grantedGroups: grantedGroups) else {
            return .missingGroupID
        }
        guard let url = containerURL(id) else {
            return .unavailable(groupID: id)
        }
        return .ready(groupID: id, url: url)
    }
}
