import Foundation
@testable import CodexBarLiteCore

struct Fixture {
    let repository: AccountRepository
    let account: Account

    init(managed: Bool = true, expired: Bool = false) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        self.repository = AccountRepository(root: root)
        self.account = Account(
            name: "Fixture",
            externalHome: managed ? nil : root.appendingPathComponent("external").path)
        let home = self.repository.home(for: self.account)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let data = try Self.auth(expiration: expired ? 1 : 4_000_000_000)
        try data.write(to: home.appendingPathComponent("auth.json"))
    }

    func clean() { try? FileManager.default.removeItem(at: self.repository.root) }

    static func jwt(_ claims: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: claims)
        let encoded = data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return "header.\(encoded).signature"
    }

    static func auth(expiration: Int = 4_000_000_000, refresh: String = "fixture-refresh") throws -> Data {
        let access = try Self.jwt([
            "exp": expiration,
            "https://api.openai.com/auth": ["chatgpt_account_id": "account-a"],
        ])
        let identity = try Self.jwt(["email": "fixture@example.com"])
        return try JSONSerialization.data(withJSONObject: [
            "auth_mode": "chatgpt", "metadata": "preserve-me",
            "tokens": ["access_token": access, "refresh_token": refresh, "id_token": identity],
        ])
    }

    static let usage = Data("""
    {"account_id":"account-a","plan_type":"plus","rate_limit":{
      "primary_window":{"used_percent":25,"reset_at":2000000000,"limit_window_seconds":18000},
      "secondary_window":{"used_percent":60,"reset_at":2000300000,"limit_window_seconds":604800}}}
    """.utf8)
}

actor StubTransport: HTTPTransport {
    var responses: [HTTPResponse]
    private(set) var requests: [URLRequest] = []

    init(_ responses: [HTTPResponse]) { self.responses = responses }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        self.requests.append(request)
        guard !self.responses.isEmpty else { throw LiteError.invalidResponse }
        return self.responses.removeFirst()
    }
}
