import Foundation
import Testing
@testable import CodexBarLiteCore

struct ClientTests {
    @Test func `owned expired tokens rotate once and use the new bearer`() async throws {
        let fixture = try Fixture(expired: true)
        defer { fixture.clean() }
        let transport = StubTransport([
            HTTPResponse(data: Data("{\"access_token\":\"rotated\",\"refresh_token\":\"next\"}".utf8), status: 200),
            HTTPResponse(data: Fixture.usage, status: 200),
        ])
        let client = UsageClient(repository: fixture.repository, transport: transport)
        _ = try await client.fetch(account: fixture.account)
        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests[0].url?.host == "auth.openai.com")
        #expect(requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer rotated")
        #expect(requests[1].value(forHTTPHeaderField: "ChatGPT-Account-Id") == "account-a")
        #expect(try Credentials.load(home: fixture.repository.home(for: fixture.account)).refreshToken == "next")
    }

    @Test func `expired linked tokens never rotate or modify another apps auth`() async throws {
        let fixture = try Fixture(managed: false, expired: true)
        defer { fixture.clean() }
        let path = fixture.repository.home(for: fixture.account).appendingPathComponent("auth.json")
        let before = try Data(contentsOf: path)
        let transport = StubTransport([
            HTTPResponse(data: Data(), status: 401), HTTPResponse(data: Data(), status: 401),
        ])
        let client = UsageClient(repository: fixture.repository, transport: transport)
        await #expect(throws: (any Error).self) { try await client.fetch(account: fixture.account) }
        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.url?.host == "chatgpt.com" })
        #expect(try Data(contentsOf: path) == before)
    }

    @Test func `rate limiting does not enter a retry loop`() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let transport = StubTransport([HTTPResponse(data: Data(), status: 429)])
        let client = UsageClient(repository: fixture.repository, transport: transport)
        await #expect(throws: (any Error).self) { try await client.fetch(account: fixture.account) }
        #expect(await transport.requests.count == 1)
    }

    @Test func `mismatched account data is rejected`() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let data = try Data(#require(String(data: Fixture.usage, encoding: .utf8)?
                .replacingOccurrences(of: "account-a", with: "account-b").utf8))
        let transport = StubTransport([HTTPResponse(data: data, status: 200)])
        let client = UsageClient(repository: fixture.repository, transport: transport)
        await #expect(throws: (any Error).self) { try await client.fetch(account: fixture.account) }
    }
}
