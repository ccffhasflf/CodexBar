import Foundation

public struct HTTPResponse: Sendable {
    public let data: Data
    public let status: Int

    public init(data: Data, status: Int) { self.data = data; self.status = status }
}

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}

public final class URLSessionTransport: HTTPTransport, Sendable {
    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 45
        self.session = URLSession(configuration: config)
    }

    deinit { self.session.invalidateAndCancel() }

    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        let (data, response) = try await self.session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw LiteError.invalidResponse }
        return HTTPResponse(data: data, status: response.statusCode)
    }
}

public protocol UsageLoading: Sendable {
    func fetch(account: Account) async throws -> UsageSnapshot
}

/// The app's refresh controller serializes requests. No transcripts, cookies or usage history are read.
public struct UsageClient: UsageLoading, Sendable {
    private let repository: AccountRepository
    private let transport: any HTTPTransport

    public init(repository: AccountRepository, transport: any HTTPTransport = URLSessionTransport()) {
        self.repository = repository
        self.transport = transport
    }

    public func fetch(account: Account) async throws -> UsageSnapshot {
        let home = self.repository.home(for: account)
        var credentials = try Credentials.load(home: home)
        let refreshedBeforeFetch = account.isManaged && credentials.needsRefresh()
        if refreshedBeforeFetch {
            credentials = try await self.refresh(credentials, home: home)
        }
        try Task.checkCancellation()
        var response = try await self.usage(credentials)
        if response.status == 401 {
            if account.isManaged {
                guard !refreshedBeforeFetch else { throw LiteError.loginRequired }
                credentials = try await self.refresh(credentials, home: home)
            } else {
                // The owning Codex app may have just rotated the system credentials.
                credentials = try Credentials.load(home: home)
            }
            try Task.checkCancellation()
            response = try await self.usage(credentials)
        }
        guard response.status != 401 else { throw LiteError.loginRequired }
        guard response.status == 200 else { throw LiteError.http(response.status) }
        let snapshot = try UsageSnapshot.decode(response.data, email: credentials.email)
        if let expected = credentials.accountID, let actual = snapshot.accountID, expected != actual {
            throw LiteError.accountMismatch
        }
        return snapshot
    }

    private func usage(_ credentials: Credentials) async throws -> HTTPResponse {
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CodexBarLite", forHTTPHeaderField: "User-Agent")
        if let id = credentials.accountID { request.setValue(id, forHTTPHeaderField: "ChatGPT-Account-Id") }
        return try await self.transport.send(request)
    }

    private func refresh(_ credentials: Credentials, home: URL) async throws -> Credentials {
        guard !credentials.refreshToken.isEmpty else { throw LiteError.loginRequired }
        var request = URLRequest(url: URL(string: "https://auth.openai.com/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "client_id": "app_EMoamEEZ73f0CkXaXp7hrann",
            "grant_type": "refresh_token", "refresh_token": credentials.refreshToken,
            "scope": "openid profile email",
        ])
        let response = try await self.transport.send(request)
        guard response.status != 400, response.status != 401 else { throw LiteError.loginRequired }
        guard response.status == 200 else { throw LiteError.http(response.status) }
        // A successful token rotation must be persisted even if cancellation arrived with the response.
        return try Credentials.saveRefresh(response.data, home: home, expected: credentials)
    }
}
