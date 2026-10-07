import Foundation
import Testing
@testable import CodexBarLite
@testable import CodexBarLiteCore

struct ResetCreditsTests {
    private static let inventory = Data("""
    {"available_count":99,"credits":[
      {"id":"later","reset_type":"weekly","status":"available",
       "granted_at":"2026-10-01T00:00:00Z","expires_at":"2099-01-02T00:00:00.123Z"},
      {"id":"used","reset_type":"weekly","status":"redeemed","granted_at":"2026-10-01T00:00:00Z"},
      {"id":"expired","reset_type":"weekly","status":"available",
       "granted_at":"2026-10-01T00:00:00Z","expires_at":"2000-01-01T00:00:00Z"},
      {"id":"unknown","reset_type":"weekly","status":"new-status","granted_at":"2026-10-01T00:00:00Z"},
      {"id":"no-expiry","reset_type":"weekly","status":"available","granted_at":"2026-10-01T00:00:00Z"},
      {"id":"first","reset_type":"weekly","status":"available",
       "granted_at":"2026-10-01T00:00:00Z","expires_at":"2099-01-01T00:00:00Z"}]}
    """.utf8)

    @Test func `reset inventory uses winning credentials and leaves current login unchanged`() async throws {
        let fixture = try Fixture(managed: false)
        defer { fixture.clean() }
        let file = fixture.repository.home(for: fixture.account).appendingPathComponent("auth.json")
        let before = try Data(contentsOf: file)
        let transport = StubTransport([
            HTTPResponse(data: Fixture.usage, status: 200), HTTPResponse(data: Self.inventory, status: 200),
        ])
        let snapshot = try await UsageClient(repository: fixture.repository, transport: transport)
            .fetch(account: fixture.account)
        let credits = try #require(snapshot.resetCredits)
        #expect(credits.availableCount == 99)
        #expect(credits.availableInventory(at: snapshot.updatedAt).credits.map(\.id) == ["first", "later", "no-expiry"])
        #expect(credits.credits.contains { $0.status == .unknown("new-status") })
        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests[1].url?.path == "/backend-api/wham/rate-limit-reset-credits")
        #expect(requests[1].timeoutInterval == 4)
        #expect(requests[1].httpMethod == "GET")
        #expect(requests[1].value(forHTTPHeaderField: "Authorization") == requests[0]
            .value(forHTTPHeaderField: "Authorization"))
        #expect(requests[1].value(forHTTPHeaderField: "ChatGPT-Account-ID") == "account-a")
        #expect(requests[1].value(forHTTPHeaderField: "OpenAI-Beta") == "codex-1")
        #expect(requests[1].value(forHTTPHeaderField: "originator") == "Codex Desktop")
        #expect(try Data(contentsOf: file) == before)
    }

    @Test(arguments: [401, 403, 429, 503])
    func `unavailable reset credits preserve quota without retry`(status: Int) async throws {
        let fixture = try Fixture(managed: false)
        defer { fixture.clean() }
        let transport = StubTransport([
            HTTPResponse(data: Fixture.usage, status: 200), HTTPResponse(data: Data(), status: status),
        ])
        let snapshot = try await UsageClient(repository: fixture.repository, transport: transport)
            .fetch(account: fixture.account)
        #expect(snapshot.windows.count == 2)
        #expect(snapshot.resetCredits == nil)
        #expect(await transport.requests.count == 2)
    }

    @Test(arguments: [
        "not-json", #"{"credits":[],"available_count":-1}"#,
        """
        {"credits":[{"id":"bad","reset_type":"weekly","status":"available","granted_at":"invalid"}],
         "available_count":1}
        """,
    ])
    func `malformed inventory does not hide successful quota`(payload: String) async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let transport = StubTransport([
            HTTPResponse(data: Fixture.usage, status: 200), HTTPResponse(data: Data(payload.utf8), status: 200),
        ])
        let snapshot = try await UsageClient(repository: fixture.repository, transport: transport)
            .fetch(account: fixture.account)
        #expect(snapshot.windows.count == 2)
        #expect(snapshot.resetCredits == nil)
    }

    @Test func `available reset cards can be displayed before quota windows exist`() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let transport = StubTransport([
            HTTPResponse(data: Data(#"{"account_id":"account-a","plan_type":"pro"}"#.utf8), status: 200),
            HTTPResponse(data: Self.inventory, status: 200),
        ])
        let snapshot = try await UsageClient(repository: fixture.repository, transport: transport)
            .fetch(account: fixture.account)
        #expect(snapshot.windows.isEmpty)
        #expect(snapshot.resetCredits?.availableInventory(at: Date()).count == 3)
    }

    @Test func `no quota and no active reset cards remains a no quota error`() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let transport = StubTransport([
            HTTPResponse(data: Data(#"{"account_id":"account-a"}"#.utf8), status: 200),
            HTTPResponse(data: Data(#"{"credits":[],"available_count":0}"#.utf8), status: 200),
        ])
        await #expect(throws: (any Error).self) {
            try await UsageClient(repository: fixture.repository, transport: transport).fetch(account: fixture.account)
        }
    }

    @Test func `supplement cancellation is propagated`() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let transport = CancellingResetTransport()
        await #expect(throws: CancellationError.self) {
            try await UsageClient(repository: fixture.repository, transport: transport).fetch(account: fixture.account)
        }
    }

    @Test func `auth changing during quota fetch cannot mix accounts in the supplement`() async throws {
        let fixture = try Fixture(managed: false)
        defer { fixture.clean() }
        let home = fixture.repository.home(for: fixture.account)
        let oldToken = try Credentials.load(home: home).accessToken
        let newToken = try Fixture.jwt([
            "exp": 4_000_000_000, "https://api.openai.com/auth": ["chatgpt_account_id": "account-b"],
        ])
        let replacement = try JSONSerialization.data(withJSONObject: [
            "tokens": ["access_token": newToken, "refresh_token": "other"],
        ])
        let transport = SwitchingAuthTransport(file: home.appendingPathComponent("auth.json"), replacement: replacement)
        _ = try await UsageClient(repository: fixture.repository, transport: transport).fetch(account: fixture.account)
        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer \(oldToken)")
        #expect(requests[1].value(forHTTPHeaderField: "ChatGPT-Account-ID") == "account-a")
        #expect(try Data(contentsOf: home.appendingPathComponent("auth.json")) == replacement)
    }

    @Test func `original card presentation expires live and keeps all details in help`() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let credits = (0..<6).map { index in
            CodexRateLimitResetCredit(
                id: "card-\(index)",
                resetType: "weekly",
                status: .available,
                grantedAt: now,
                expiresAt: now.addingTimeInterval(Double(index + 1) * 3600),
                redeemStartedAt: nil,
                redeemedAt: nil,
                title: nil,
                description: nil)
        }
        let snapshot = CodexRateLimitResetCreditsSnapshot(credits: credits, availableCount: 6, updatedAt: now)
        let presentation = try #require(LimitResetCreditsPresentation.make(
            snapshot: snapshot, resetStyle: .countdown, now: now))
        #expect(presentation.text == "6 次可用")
        #expect(presentation.expirySummaryText == "1h · 2h · 3h · 4h · +2")
        #expect(presentation.helpText.split(separator: "\n").count == 6)
        let later = try #require(LimitResetCreditsPresentation.make(
            snapshot: snapshot, resetStyle: .absolute, now: now.addingTimeInterval(3600)))
        #expect(later.text == "5 次可用")
        #expect(!later.expirySummaryText.contains("in "))
        #expect(LimitResetCreditsPresentation.make(
            snapshot: snapshot, resetStyle: .countdown, now: now.addingTimeInterval(21600)) == nil)
    }

    @Test func `reset time style defaults for old configuration and persists new selection`() throws {
        let old = Data(#"{"accounts":[],"refreshMinutes":5,"cliPath":""}"#.utf8)
        var config = try JSONDecoder().decode(Configuration.self, from: old)
        #expect(config.resetTimeDisplayStyle == .countdown)
        config.resetTimeDisplayStyle = .absolute
        #expect(try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(config))
            .resetTimeDisplayStyle == .absolute)
        let snapshot = try UsageSnapshot.decode(Fixture.usage, email: nil)
        let window = try #require(snapshot.windows.first)
        let metric = QuotaPresentation.metric(window: window, now: snapshot.updatedAt, resetStyle: .absolute)
        #expect(try metric.resetText == L("Resets %@", UsageFormatter.resetDescription(
            from: #require(window.resetsAt), now: snapshot.updatedAt)))
    }
}

private struct CancellingResetTransport: HTTPTransport {
    func send(_ request: URLRequest) async throws -> HTTPResponse {
        if request.url?.path.hasSuffix("reset-credits") == true { throw CancellationError() }
        return HTTPResponse(data: Fixture.usage, status: 200)
    }
}

private actor SwitchingAuthTransport: HTTPTransport {
    let file: URL
    let replacement: Data
    private(set) var requests: [URLRequest] = []

    init(file: URL, replacement: Data) { self.file = file; self.replacement = replacement }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        self.requests.append(request)
        if self.requests.count == 1 {
            try self.replacement.write(to: self.file)
            return HTTPResponse(data: Fixture.usage, status: 200)
        }
        return HTTPResponse(data: Data(#"{"credits":[],"available_count":0}"#.utf8), status: 200)
    }
}
