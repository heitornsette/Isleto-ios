import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Where the cloud is. Typed once on each device ("Conectar à nuvem") and kept in the
/// Keychain; never in the repository.
public struct CloudConfig: Codable, Equatable, Sendable {
    /// "https://<project>.supabase.co"
    public var url: String
    /// Publishable key ("sb_publishable_..."). Safe in apps: Row Level Security protects the data.
    public var publishableKey: String

    public init(url: String, publishableKey: String) {
        self.url = url
        self.publishableKey = publishableKey
    }

    /// Trimmed, without the trailing slash, https only. Nil if it is not a usable address.
    public func normalized() -> CloudConfig? {
        var url = url.trimmingCharacters(in: .whitespacesAndNewlines)
        while url.hasSuffix("/") { url.removeLast() }
        let key = publishableKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: url), parsed.scheme == "https", parsed.host?.isEmpty == false, !key.isEmpty else {
            return nil
        }
        return CloudConfig(url: url, publishableKey: key)
    }
}

/// The signed-in user's tokens. The password is never stored: only the refresh token,
/// which Supabase replaces at every refresh.
public struct CloudSession: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public var email: String

    public init(accessToken: String, refreshToken: String, expiresAt: Date, email: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.email = email
    }
}

public enum CloudError: LocalizedError, Equatable {
    case invalidConfig
    case notSignedIn
    case auth(String)
    case http(Int, String)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .invalidConfig: "Endereço ou chave inválidos. O endereço começa com https://."
        case .notSignedIn: "Sessão expirada. Conecte de novo."
        case .auth(let message): "Login recusado: \(message)"
        case .http(let status, let message): "Erro do servidor (\(status)): \(message)"
        case .invalidResponse: "Resposta inválida do servidor."
        }
    }
}

/// Sends HTTP requests. URLSession in the app; a fake in the tests.
public protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionHTTPClient: HTTPClient {
    public init() {}

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CloudError.invalidResponse }
        return (data, http)
    }
}

/// Talks to Supabase: password sign-in, token refresh and the sync functions.
public actor SupabaseClient {
    public let config: CloudConfig
    private var session: CloudSession?
    private let http: any HTTPClient
    /// Called with every new session (to save it) and with nil when it is no longer valid.
    private let onSessionChange: @Sendable (CloudSession?) -> Void

    public init(
        config: CloudConfig,
        session: CloudSession? = nil,
        http: any HTTPClient = URLSessionHTTPClient(),
        onSessionChange: @escaping @Sendable (CloudSession?) -> Void = { _ in }
    ) {
        self.config = config
        self.session = session
        self.http = http
        self.onSessionChange = onSessionChange
    }

    public var currentSession: CloudSession? { session }

    /// Signs in with e-mail and password (POST /auth/v1/token?grant_type=password).
    @discardableResult
    public func signIn(email: String, password: String) async throws -> CloudSession {
        let body: JSONValue = .object([
            "email": .string(email.trimmingCharacters(in: .whitespacesAndNewlines)),
            "password": .string(password),
        ])
        let new = try await requestToken(grant: "password", body: body)
        setSession(new)
        return new
    }

    /// Calls a database function (POST /rest/v1/rpc/<name>) as the signed-in user.
    /// Refreshes the access token when it is about to expire, and once more on a 401.
    public func rpc(_ name: String, _ body: JSONValue) async throws -> JSONValue {
        let token = try await validAccessToken()
        let (data, response) = try await post(path: "/rest/v1/rpc/\(name)", body: body, bearer: token)
        if response.statusCode == 401 {
            try await refresh()
            guard let retryToken = session?.accessToken else { throw CloudError.notSignedIn }
            let (retryData, retryResponse) = try await post(path: "/rest/v1/rpc/\(name)", body: body, bearer: retryToken)
            return try decode(retryData, retryResponse)
        }
        return try decode(data, response)
    }

    private func validAccessToken(now: Date = .now) async throws -> String {
        guard let session else { throw CloudError.notSignedIn }
        if session.expiresAt.timeIntervalSince(now) > 60 {
            return session.accessToken
        }
        try await refresh()
        guard let fresh = self.session else { throw CloudError.notSignedIn }
        return fresh.accessToken
    }

    private func refresh() async throws {
        guard let current = session else { throw CloudError.notSignedIn }
        do {
            let new = try await requestToken(
                grant: "refresh_token",
                body: .object(["refresh_token": .string(current.refreshToken)]),
                email: current.email
            )
            setSession(new)
        } catch CloudError.auth {
            // The refresh token was revoked or already used: sign in again.
            setSession(nil)
            throw CloudError.notSignedIn
        }
    }

    private func setSession(_ new: CloudSession?) {
        session = new
        onSessionChange(new)
    }

    private func requestToken(grant: String, body: JSONValue, email: String? = nil) async throws -> CloudSession {
        let (data, response) = try await post(path: "/auth/v1/token?grant_type=\(grant)", body: body, bearer: nil)
        guard (200..<300).contains(response.statusCode) else {
            let message = Self.errorMessage(data)
            if (400..<500).contains(response.statusCode) { throw CloudError.auth(message) }
            throw CloudError.http(response.statusCode, message)
        }
        guard case .object(let json)? = try? JSONDecoder().decode(JSONValue.self, from: data),
              let access = json["access_token"]?.stringValue,
              let refresh = json["refresh_token"]?.stringValue
        else { throw CloudError.invalidResponse }
        let expiresIn = json["expires_in"]?.doubleValue ?? 3600
        let userEmail = json["user"]?["email"]?.stringValue ?? email ?? ""
        return CloudSession(
            accessToken: access,
            refreshToken: refresh,
            expiresAt: Date.now.addingTimeInterval(expiresIn),
            email: userEmail
        )
    }

    private func post(path: String, body: JSONValue, bearer: String?) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: config.url + path) else { throw CloudError.invalidConfig }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.publishableKey, forHTTPHeaderField: "apikey")
        if let bearer {
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(body)
        return try await http.send(request)
    }

    private func decode(_ data: Data, _ response: HTTPURLResponse) throws -> JSONValue {
        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 401 { throw CloudError.notSignedIn }
            throw CloudError.http(response.statusCode, Self.errorMessage(data))
        }
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: data) else { throw CloudError.invalidResponse }
        return value
    }

    /// Supabase errors come as {"error_description"}, {"msg"} or {"message"}.
    static func errorMessage(_ data: Data) -> String {
        if case .object(let json)? = try? JSONDecoder().decode(JSONValue.self, from: data) {
            for key in ["error_description", "msg", "message", "error"] {
                if let text = json[key]?.stringValue, !text.isEmpty { return text }
            }
        }
        return String(decoding: data.prefix(200), as: UTF8.self)
    }
}

/// The sync engine's server: isleto-cloud's sync_push and sync_pull, as the signed-in user.
public struct SupabaseTransport: SyncTransport {
    public let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    public func push(_ changes: [String: JSONValue]) async throws {
        _ = try await client.rpc("sync_push", .object(["changes": .object(changes)]))
    }

    public func pull(since: Int64, maxRows: Int) async throws -> JSONValue {
        try await client.rpc("sync_pull", .object(["since": .number(Double(since)), "max_rows": .number(Double(maxRows))]))
    }
}
