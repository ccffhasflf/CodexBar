import Foundation
import Testing
@testable import CodexBarLiteCore

struct AccountTests {
    @Test func `native credentials recover account identity from claims`() throws {
        let credentials = try Credentials.parse(Fixture.auth())
        #expect(credentials.accountID == "account-a")
        #expect(credentials.email == "fixture@example.com")
        #expect(!credentials.needsRefresh())
        #expect(try Credentials.parse(Fixture.auth(expiration: 1)).needsRefresh())
    }

    @Test func `API key accounts are not used as subscription tokens`() {
        #expect(throws: (any Error).self) {
            try Credentials.parse(Data("{\"OPENAI_API_KEY\":\"fixture-key\"}".utf8))
        }
    }

    @Test func `configuration roundtrips and removing a link preserves external credentials`() throws {
        let fixture = try Fixture(managed: false)
        defer { fixture.clean() }
        var config = Configuration()
        config.accounts = [fixture.account]
        config.selectedID = fixture.account.id
        try fixture.repository.save(config)
        #expect(try fixture.repository.load().selectedID == fixture.account.id)
        let file = fixture.repository.home(for: fixture.account).appendingPathComponent("auth.json")
        let before = try Data(contentsOf: file)
        try fixture.repository.removeCredentials(for: fixture.account)
        #expect(try Data(contentsOf: file) == before)
    }

    @Test func `invalid config is preserved and never silently replaced`() throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let bad = Data("not json".utf8)
        try bad.write(to: fixture.repository.configurationURL)
        #expect(throws: (any Error).self) { try fixture.repository.load() }
        #expect(try Data(contentsOf: fixture.repository.configurationURL) == bad)
    }

    @Test func `removing a managed account deletes only that account home`() throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let other = Account(name: "Other")
        try fixture.repository.prepare(other)
        try fixture.repository.removeCredentials(for: fixture.account)
        #expect(!FileManager.default.fileExists(atPath: fixture.repository.home(for: fixture.account).path))
        #expect(FileManager.default.fileExists(atPath: fixture.repository.home(for: other).path))
    }

    @Test func `refresh preserves metadata and writes private credentials`() throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let home = fixture.repository.home(for: fixture.account)
        let old = try Credentials.load(home: home)
        let response = Data("{\"access_token\":\"new-access\",\"refresh_token\":\"new-refresh\"}".utf8)
        _ = try Credentials.saveRefresh(response, home: home, expected: old)
        let url = home.appendingPathComponent("auth.json")
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        #expect(root?["metadata"] as? String == "preserve-me")
        #expect(try Credentials.load(home: home).refreshToken == "new-refresh")
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o600)
    }

    @Test func `refresh never overwrites credentials changed by a concurrent login`() throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let home = fixture.repository.home(for: fixture.account)
        let old = try Credentials.load(home: home)
        let changed = try Fixture.auth(refresh: "another-login")
        try changed.write(to: home.appendingPathComponent("auth.json"))
        let response = Data("{\"access_token\":\"stale-rotation\"}".utf8)
        let result = try Credentials.saveRefresh(response, home: home, expected: old)
        #expect(result.refreshToken == "another-login")
        #expect(try Data(contentsOf: home.appendingPathComponent("auth.json")) == changed)
    }
}
