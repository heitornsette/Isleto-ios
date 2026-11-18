import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import IsletoCore

/// Records the requests and answers from a script, in order.
actor FakeHTTP: HTTPClient {
    struct Answer {
        let status: Int
        let body: String
    }

    private var answers: [Answer]
    private(set) var requests: [URLRequest] = []

    init(_ answers: [Answer]) {
        self.answers = answers
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let answer = answers.isEmpty ? Answer(status: 500, body: "{}") : answers.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: answer.status, httpVersion: nil, headerFields: nil)!
        return (Data(answer.body.utf8), response)
    }

    func json(_ index: Int) -> JSONValue? {
        guard index < requests.count, let body = requests[index].httpBody else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: body)
    }
}

/// Collects the sessions the client asks to save.
final class SessionLog: @unchecked Sendable {
    private let lock = NSLock()
    private var saved: [CloudSession?] = []

    func record(_ session: CloudSession?) {
        lock.withLock { saved.append(session) }
    }

    var all: [CloudSession?] { lock.withLock { saved } }
}

final class SupabaseClientTests: XCTestCase {
    private let config = CloudConfig(url: "https://abc.supabase.co", publishableKey: "sb_publishable_test")
    private let tokenBody = #"{"access_token":"A1","refresh_token":"R1","expires_in":3600,"user":{"email":"eu@example.com"}}"#

    func testConfigIsNormalized() {
        XCTAssertEqual(
            CloudConfig(url: " https://abc.supabase.co/ ", publishableKey: " key ").normalized(),
            CloudConfig(url: "https://abc.supabase.co", publishableKey: "key")
        )
        XCTAssertNil(CloudConfig(url: "http://abc.supabase.co", publishableKey: "key").normalized(), "https only")
        XCTAssertNil(CloudConfig(url: "abc", publishableKey: "key").normalized())
        XCTAssertNil(CloudConfig(url: "https://abc.supabase.co", publishableKey: " ").normalized())
    }

    func testSignInSendsThePasswordGrantAndSavesTheSession() async throws {
        let http = FakeHTTP([.init(status: 200, body: tokenBody)])
        let log = SessionLog()
        let client = SupabaseClient(config: config, http: http, onSessionChange: { log.record($0) })
        let session = try await client.signIn(email: " eu@example.com ", password: "segredo")

        XCTAssertEqual(session.accessToken, "A1")
        XCTAssertEqual(session.email, "eu@example.com")
        XCTAssertEqual(log.all, [session])
        let request = await http.requests[0]
        XCTAssertEqual(request.url?.absoluteString, "https://abc.supabase.co/auth/v1/token?grant_type=password")
        XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "sb_publishable_test")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let body = await http.json(0)
        XCTAssertEqual(body?["email"]?.stringValue, "eu@example.com")
    }

    func testWrongPasswordIsAnAuthError() async {
        let http = FakeHTTP([.init(status: 400, body: #"{"code":400,"error_code":"invalid_credentials","msg":"Invalid login credentials"}"#)])
        let client = SupabaseClient(config: config, http: http)
        do {
            try await client.signIn(email: "eu@example.com", password: "errada")
            XCTFail("should fail")
        } catch {
            XCTAssertEqual(error as? CloudError, .auth("Invalid login credentials"))
        }
    }

    func testRPCUsesTheUserTokenAndIntegerNumbers() async throws {
        let http = FakeHTTP([.init(status: 200, body: #"{"cursor":7,"has_more":false}"#)])
        let session = CloudSession(accessToken: "A1", refreshToken: "R1", expiresAt: .now.addingTimeInterval(3600), email: "eu@example.com")
        let client = SupabaseClient(config: config, session: session, http: http)
        let page = try await SupabaseTransport(client: client).pull(since: 5, maxRows: 1000)

        XCTAssertEqual(page["cursor"]?.doubleValue, 7)
        let request = await http.requests[0]
        XCTAssertEqual(request.url?.absoluteString, "https://abc.supabase.co/rest/v1/rpc/sync_pull")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer A1")
        let text = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        XCTAssertTrue(text.contains(#""since":5"#), text)
        XCTAssertTrue(text.contains(#""max_rows":1000"#), text)
    }

    func testAnExpiringTokenIsRefreshedFirst() async throws {
        let http = FakeHTTP([
            .init(status: 200, body: #"{"access_token":"A2","refresh_token":"R2","expires_in":3600}"#),
            .init(status: 200, body: #"{"applied":1}"#),
        ])
        let log = SessionLog()
        let old = CloudSession(accessToken: "A1", refreshToken: "R1", expiresAt: .now.addingTimeInterval(10), email: "eu@example.com")
        let client = SupabaseClient(config: config, session: old, http: http, onSessionChange: { log.record($0) })
        try await SupabaseTransport(client: client).push(["habits": .array([])])

        let refresh = await http.requests[0]
        XCTAssertEqual(refresh.url?.absoluteString, "https://abc.supabase.co/auth/v1/token?grant_type=refresh_token")
        let refreshBody = await http.json(0)
        XCTAssertEqual(refreshBody?["refresh_token"]?.stringValue, "R1")
        let call = await http.requests[1]
        XCTAssertEqual(call.value(forHTTPHeaderField: "Authorization"), "Bearer A2")
        XCTAssertEqual(log.all.first??.refreshToken, "R2", "the new refresh token is saved (Supabase rotates it)")
        XCTAssertEqual(log.all.first??.email, "eu@example.com", "the e-mail is kept")
    }

    func testA401RefreshesOnceAndRetries() async throws {
        let http = FakeHTTP([
            .init(status: 401, body: #"{"message":"JWT expired"}"#),
            .init(status: 200, body: #"{"access_token":"A2","refresh_token":"R2","expires_in":3600}"#),
            .init(status: 200, body: #"{"applied":0}"#),
        ])
        let session = CloudSession(accessToken: "A1", refreshToken: "R1", expiresAt: .now.addingTimeInterval(3600), email: "eu@example.com")
        let client = SupabaseClient(config: config, session: session, http: http)
        let result = try await client.rpc("sync_push", .object(["changes": .object([:])]))
        XCTAssertEqual(result["applied"]?.doubleValue, 0)
        let count = await http.requests.count
        XCTAssertEqual(count, 3)
    }

    func testARevokedRefreshTokenSignsOut() async {
        let http = FakeHTTP([.init(status: 400, body: #"{"error":"invalid_grant","error_description":"Refresh Token Not Found"}"#)])
        let log = SessionLog()
        let old = CloudSession(accessToken: "A1", refreshToken: "R1", expiresAt: .distantPast, email: "eu@example.com")
        let client = SupabaseClient(config: config, session: old, http: http, onSessionChange: { log.record($0) })
        do {
            _ = try await client.rpc("sync_pull", .object([:]))
            XCTFail("should fail")
        } catch {
            XCTAssertEqual(error as? CloudError, .notSignedIn)
        }
        XCTAssertEqual(log.all.count, 1)
        XCTAssertNil(log.all[0], "the saved session is cleared")
    }

    func testServerErrorsKeepTheMessage() async {
        let http = FakeHTTP([.init(status: 400, body: #"{"code":"23502","message":"null value in column \"name\""}"#)])
        let session = CloudSession(accessToken: "A1", refreshToken: "R1", expiresAt: .now.addingTimeInterval(3600), email: "eu@example.com")
        let client = SupabaseClient(config: config, session: session, http: http)
        do {
            _ = try await client.rpc("sync_push", .object([:]))
            XCTFail("should fail")
        } catch {
            XCTAssertEqual(error as? CloudError, .http(400, #"null value in column "name""#))
        }
    }
}
