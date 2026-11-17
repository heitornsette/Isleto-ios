import Foundation
import IsletoCore

/// Access to the App Group database, used by the app and by the widget extension.
/// Compiled into both targets.
enum SharedData {
    enum Failure: LocalizedError {
        case container(SharedContainer.Status)

        var errorDescription: String? {
            switch self {
            case .container(.missingGroupID):
                "Info.plist sem o App Group (erro de build)."
            case .container(.unavailable(let id)):
                "App Group \(id) indisponível: a assinatura não concedeu o grupo."
            case .container(.ready):
                nil
            }
        }
    }

    /// Each process reads its own bundle: the app's profile in the app, the
    /// extension's profile in the widget. Both are granted the same group.
    static func status() -> SharedContainer.Status {
        SharedContainer.resolve(
            infoDictionary: Bundle.main.infoDictionary,
            grantedGroups: ProvisioningProfile.load(bundleURL: Bundle.main.bundleURL)?.appGroups
        )
    }

    static func databaseURL() throws -> URL {
        let status = status()
        guard case .ready(_, let url) = status else {
            throw Failure.container(status)
        }
        return url.appending(path: IsletoDatabase.fileName)
    }

    static func store() throws -> IsletoStore {
        IsletoStore(database: try IsletoDatabase.open(at: databaseURL()))
    }
}
