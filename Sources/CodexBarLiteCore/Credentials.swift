import Foundation

/// Native Codex auth.json handling, adapted from upstream's CodexOAuthCredentialsStore.
/// External homes are read-only; only Lite-owned login homes are eligible for rotation.
struct Credentials: Sendable {
    let accessToken: String
    let refreshToken: String
    let idToken: String?
    let accountID: String?
    let email: String?
    let lastRefresh: Date?
    let expiresAt: Date?

    func needsRefresh(now: Date = Date()) -> Bool {
        if let expiresAt { return expiresAt.timeIntervalSince(now) <= 300 }
        return self.lastRefresh.map { now.timeIntervalSince($0) > 8 * 86400 } ?? true
    }

    static func load(home: URL) throws -> Self {
        let path = home.appendingPathComponent("auth.json")
        guard FileManager.default.fileExists(atPath: path.path) else { throw LiteError.missingCredentials }
        return try Self.parse(Data(contentsOf: path))
    }

    static func parse(_ data: Data) throws -> Self {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LiteError.invalidCredentials
        }
        if let key = nonEmpty(root["OPENAI_API_KEY"] as? String), !key.isEmpty { throw LiteError.apiKeyAccount }
        guard let tokens = root["tokens"] as? [String: Any],
              let access = nonEmpty(tokens["access_token"] as? String ?? tokens["accessToken"] as? String)
        else { throw LiteError.invalidCredentials }
        let idToken = tokens["id_token"] as? String ?? tokens["idToken"] as? String
        let identity = Self.claims(idToken)
        let accessClaims = Self.claims(access)
        let accountID = self.nonEmpty(tokens["account_id"] as? String ?? tokens["accountId"] as? String)
            ?? self.accountID(identity) ?? self.accountID(accessClaims)
        let refreshDate = (root["last_refresh"] as? String).flatMap { Self.date($0) }
        let expiration = (accessClaims["exp"] as? NSNumber).flatMap { number -> Date? in
            let value = number.doubleValue
            guard value.isFinite, value > 0, value < 253_402_300_800 else { return nil }
            return Date(timeIntervalSince1970: value)
        }
        let profile = accessClaims["https://api.openai.com/profile"] as? [String: Any]
        return Self(
            accessToken: access,
            refreshToken: tokens["refresh_token"] as? String ?? tokens["refreshToken"] as? String ?? "",
            idToken: idToken,
            accountID: accountID,
            email: self.nonEmpty(identity["email"] as? String ?? profile?["email"] as? String),
            lastRefresh: refreshDate,
            expiresAt: expiration)
    }

    static func claims(_ token: String?) -> [String: Any] {
        guard let token else { return [:] }
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return [:] }
        var encoded = String(parts[1]).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        // Claims are display/routing hints; the server validates the bearer token.
        return payload
    }

    private static func accountID(_ claims: [String: Any]) -> String? {
        self.nonEmpty(claims["chatgpt_account_id"] as? String)
            ?? self
            .nonEmpty((claims["https://api.openai.com/auth"] as? [String: Any])?["chatgpt_account_id"] as? String)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter.date(from: value)
    }

    /// Preserve native auth metadata and publish rotated credentials before querying usage.
    static func saveRefresh(_ response: Data, home: URL, expected: Credentials, now: Date = Date()) throws -> Self {
        guard let fresh = try JSONSerialization.jsonObject(with: response) as? [String: Any],
              let access = nonEmpty(fresh["access_token"] as? String)
        else { throw LiteError.invalidResponse }
        let url = home.appendingPathComponent("auth.json")
        let oldData = try Data(contentsOf: url)
        let current = try Self.parse(oldData)
        // A concurrent native login must not be overwritten by a stale refresh response.
        guard current.accessToken == expected.accessToken, current.refreshToken == expected.refreshToken else {
            return current
        }
        guard var root = try JSONSerialization.jsonObject(with: oldData) as? [String: Any] else {
            throw LiteError.invalidCredentials
        }
        var tokens = root["tokens"] as? [String: Any] ?? [:]
        tokens["access_token"] = access
        tokens["refresh_token"] = self.nonEmpty(fresh["refresh_token"] as? String) ?? expected.refreshToken
        tokens["id_token"] = self.nonEmpty(fresh["id_token"] as? String) ?? expected.idToken
        if let accountID = expected.accountID { tokens["account_id"] = accountID }
        root["tokens"] = tokens
        root["last_refresh"] = ISO8601DateFormatter().string(from: now)
        let data = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        let credentials = try Self.parse(data)
        try CredentialFileWriter.writePrivate(data, to: url)
        return credentials
    }
}
