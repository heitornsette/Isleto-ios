import Foundation

/// Locates the App Group container shared by the app and the widget extension.
///
/// No fallback on purpose: if the App Group is not granted by the signature, the app
/// must say so, so the feasibility test shows the real result.
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

    /// The App Group identifier, preferring the one written by AltStore/SideStore.
    public static func groupID(infoDictionary: [String: Any]?) -> String? {
        if let rewritten = infoDictionary?[altStoreKey] as? [String], let first = rewritten.first, !first.isEmpty {
            return first
        }
        if let id = infoDictionary?[infoPlistKey] as? String, !id.isEmpty {
            return id
        }
        return nil
    }

    public static func resolve(
        infoDictionary: [String: Any]?,
        containerURL: (String) -> URL? = { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
    ) -> Status {
        guard let id = groupID(infoDictionary: infoDictionary) else {
            return .missingGroupID
        }
        guard let url = containerURL(id) else {
            return .unavailable(groupID: id)
        }
        return .ready(groupID: id, url: url)
    }
}
