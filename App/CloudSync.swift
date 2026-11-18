import Foundation
import GRDB
import IsletoCore
import Observation
import WidgetKit

extension Notification.Name {
    /// The sync wrote remote changes into the local database: screens reload.
    static let isletoDataChanged = Notification.Name("isletoDataChanged")
}

/// Runs the cloud sync for the app: connection (Keychain), when to sync, and status.
/// The sync itself is IsletoCore's SyncEngine over SupabaseTransport.
@MainActor
@Observable
final class CloudSync {
    static let shared = CloudSync()

    enum Status: Equatable {
        case disconnected
        case idle
        case syncing
        case failed(String)
    }

    private(set) var status: Status = .disconnected
    private(set) var email: String?
    private(set) var lastSync: Date?
    private(set) var lastReport: SyncReport?

    private var client: SupabaseClient?
    private var running = false
    private var pending = false
    private var debounce: Task<Void, Never>?

    nonisolated private static let configAccount = "config"
    nonisolated private static let sessionAccount = "session"

    var isConnected: Bool { client != nil }

    private init() {
        if let config = Keychain.load(CloudConfig.self, account: Self.configAccount),
           let session = Keychain.load(CloudSession.self, account: Self.sessionAccount) {
            client = Self.makeClient(config, session)
            email = session.email
            status = .idle
        }
    }

    /// The client saves every new session (Supabase rotates the refresh token) and
    /// forgets it when it is revoked.
    nonisolated private static func makeClient(_ config: CloudConfig, _ session: CloudSession?) -> SupabaseClient {
        SupabaseClient(config: config, session: session) { session in
            if let session {
                Keychain.save(session, account: sessionAccount)
            } else {
                Keychain.delete(account: sessionAccount)
            }
        }
    }

    /// Signs in once; the password is used here and not stored.
    func connect(url: String, key: String, email: String, password: String) async throws {
        guard let config = CloudConfig(url: url, publishableKey: key).normalized() else {
            throw CloudError.invalidConfig
        }
        let client = Self.makeClient(config, nil)
        let session = try await client.signIn(email: email, password: password)
        Keychain.save(config, account: Self.configAccount)
        self.client = client
        self.email = session.email
        status = .idle
        await syncNow()
    }

    /// Forgets the connection. The data stays on this device, all marked to be sent again,
    /// so connecting later (to this or another account) uploads everything.
    func disconnect(message: String? = nil) {
        debounce?.cancel()
        client = nil
        email = nil
        Keychain.delete(account: Self.configAccount)
        Keychain.delete(account: Self.sessionAccount)
        status = message.map { Status.failed($0) } ?? .disconnected
        if let db = try? IsletoDatabase.open(at: SharedData.databaseURL()) {
            try? db.write { db in
                try db.execute(sql: "UPDATE sync_state SET cursor = 0, last_sync = ''")
                for table in SyncEngine.tables {
                    try db.execute(sql: "UPDATE \(table) SET dirty = 1")
                }
            }
        }
    }

    /// Syncs a few seconds after the last local change, so a burst of taps is one sync.
    func scheduleSync() {
        guard client != nil else { return }
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await self?.syncNow()
        }
    }

    /// Syncs now. A call while a sync runs makes it run once more at the end.
    func syncNow() async {
        guard client != nil else { return }
        if running {
            pending = true
            return
        }
        running = true
        repeat {
            pending = false
            await runOnce()
        } while pending && client != nil
        running = false
    }

    private func runOnce() async {
        guard let client else { return }
        status = .syncing
        do {
            let db = try IsletoDatabase.open(at: SharedData.databaseURL())
            let report = try await SyncEngine(database: db).sync(using: SupabaseTransport(client: client))
            lastReport = report
            lastSync = .now
            status = .idle
            if report.applied > 0 {
                NotificationCenter.default.post(name: .isletoDataChanged, object: nil)
                WidgetCenter.shared.reloadAllTimelines()
            }
        } catch CloudError.notSignedIn {
            disconnect(message: CloudError.notSignedIn.localizedDescription)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// One line for the diagnostics. No e-mail: diagnostics may be posted publicly.
    var diagnosticsLine: String {
        switch status {
        case .disconnected: return "desconectada"
        case .syncing: return "sincronizando"
        case .idle:
            let time = lastSync.map { $0.formatted(date: .omitted, time: .shortened) } ?? "ainda não"
            return "conectada, última sincronização: \(time)"
        case .failed(let message): return "erro: \(message)"
        }
    }
}
