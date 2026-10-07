import Foundation

public struct Account: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public let externalHome: String?

    public var isManaged: Bool {
        self.externalHome == nil
    }

    public init(id: UUID = UUID(), name: String, externalHome: String? = nil) {
        self.id = id
        self.name = name
        self.externalHome = externalHome
    }
}

public struct Configuration: Codable, Sendable {
    public var accounts: [Account] = []
    public var selectedID: UUID?
    public var refreshMinutes: Int = 5
    public var cliPath: String = ""
    public var codexHome: String?

    public init() {}

    public mutating func validate() throws {
        guard Set(self.accounts.map(\.id)).count == self.accounts.count,
              self.accounts
                  .allSatisfy({ !$0.name.isEmpty && ($0.externalHome == nil || $0.externalHome!.hasPrefix("/")) })
        else { throw LiteError.invalidConfiguration }
        if ![1, 5, 15, 30].contains(self.refreshMinutes) { self.refreshMinutes = 5 }
        if !self.accounts.contains(where: { $0.id == self.selectedID }) { self.selectedID = self.accounts.first?.id }
    }
}

public struct AccountRepository: Sendable {
    public let root: URL
    public var configurationURL: URL {
        self.root.appendingPathComponent("config.json")
    }

    public init(root: URL) { self.root = root }

    public static var standard: Self {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return Self(root: base.appendingPathComponent("CodexBarLite", isDirectory: true))
    }

    public func load() throws -> Configuration {
        guard FileManager.default.fileExists(atPath: self.configurationURL.path) else { return Configuration() }
        do {
            var config = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: self.configurationURL))
            try config.validate()
            return config
        } catch {
            throw LiteError.invalidConfiguration
        }
    }

    public func save(_ configuration: Configuration) throws {
        var checked = configuration
        try checked.validate()
        try CredentialFileWriter.writePrivate(JSONEncoder().encode(checked), to: self.configurationURL)
    }

    public func home(for account: Account) -> URL {
        if let path = account.externalHome { return URL(fileURLWithPath: path, isDirectory: true) }
        return self.root.appendingPathComponent("accounts", isDirectory: true)
            .appendingPathComponent(account.id.uuidString, isDirectory: true)
    }

    public func prepare(_ account: Account) throws {
        guard account.isManaged else { return }
        try FileManager.default.createDirectory(
            at: self.home(for: account),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
    }

    public func loginLabel(for account: Account) throws -> String {
        let credentials = try Credentials.load(home: self.home(for: account))
        return credentials.email ?? credentials.accountID ?? account.name
    }

    public func removeCredentials(for account: Account) throws {
        guard account.isManaged else { return }
        let home = self.home(for: account)
        if FileManager.default.fileExists(atPath: home.path) { try FileManager.default.removeItem(at: home) }
    }
}
