import Foundation
import Testing
@testable import CodexBarLite
@testable import CodexBarLiteCore

@MainActor
struct CurrentLoginTests {
    private func eventually(_ predicate: @MainActor () -> Bool) async -> Bool {
        for _ in 0..<100 {
            if predicate() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    @Test func `default source uses CODEX HOME and otherwise native home`() {
        let home = URL(fileURLWithPath: "/fixture-home")
        #expect(CurrentCodexHome.resolve(configured: nil, environment: [:], homeDirectory: home).path
            == "/fixture-home/.codex")
        #expect(CurrentCodexHome.resolve(
            configured: nil, environment: ["CODEX_HOME": "~/custom"], homeDirectory: home).path
            == "/fixture-home/custom")
        #expect(CurrentCodexHome.resolve(
            configured: "/selected", environment: ["CODEX_HOME": "/ignored"], homeDirectory: home).path == "/selected")
    }

    @Test func `old saved account selection does not override the current Codex home`() throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        var config = Configuration()
        config.accounts = [fixture.account]
        config.selectedID = fixture.account.id
        try fixture.repository.save(config)
        let home = fixture.repository.root.appendingPathComponent("native")
        let model = try AppModel(repository: fixture.repository, defaultHome: home, client: DemoUsageClient())
        #expect(model.currentHome.path == home.path)
        #expect(!model.currentAccount.isManaged)
        #expect(model.currentAccount.id != fixture.account.id)
    }

    @Test func `monitor detects atomic replacement deletion and recreation`() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let home = fixture.repository.home(for: fixture.account)
        let file = home.appendingPathComponent("auth.json")
        var changes = 0
        let monitor = CurrentLoginMonitor(home: home) { changes += 1 }
        monitor.start()
        defer { monitor.stop() }
        try Data("replacement".utf8).write(to: file, options: .atomic)
        #expect(await self.eventually { changes == 1 })
        try FileManager.default.removeItem(at: file)
        #expect(await self.eventually { changes == 2 })
        try Data("new login".utf8).write(to: file, options: .atomic)
        #expect(await self.eventually { changes == 3 })
    }

    @Test func `monitor detects in place writes but ignores other Codex files`() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let home = fixture.repository.home(for: fixture.account)
        var changes = 0
        let monitor = CurrentLoginMonitor(home: home) { changes += 1 }
        monitor.start()
        defer { monitor.stop() }
        try Data("unrelated".utf8).write(to: home.appendingPathComponent("config.toml"))
        try await Task.sleep(for: .milliseconds(250))
        #expect(changes == 0)
        let handle = try FileHandle(forWritingTo: home.appendingPathComponent("auth.json"))
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data("in-place change".utf8))
        try handle.close()
        #expect(await self.eventually { changes == 1 })
    }

    @Test func `monitor follows a Codex home that does not exist at launch`() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let home = fixture.repository.root.appendingPathComponent("new-home")
        var changes = 0
        let monitor = CurrentLoginMonitor(home: home) { changes += 1 }
        monitor.start()
        defer { monitor.stop() }
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try Data("login".utf8).write(to: home.appendingPathComponent("auth.json"), options: .atomic)
        #expect(await self.eventually { changes == 1 })
    }

    @Test func `account change immediately clears old quota and ignores a late old response`() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let client = SwitchingClient()
        let model = try AppModel(
            repository: fixture.repository,
            defaultHome: fixture.repository.home(for: fixture.account),
            client: client)
        model.refreshNow()
        #expect(await self.eventually { model.status?.snapshot != nil })
        let previous = model.currentAccount.id
        model.refreshNow()
        while await client.calls < 2 {
            await Task.yield()
        }
        model.followCurrentLogin()
        #expect(model.status?.snapshot == nil)
        #expect(model.currentAccount.id != previous)
        #expect(await self.eventually { model.status?.snapshot?.email == "new@example.com" })
        #expect(model.refresh.statuses.count == 1)
        #expect(model.refresh.statuses[previous] == nil)
        model.stop()
    }
}

private actor SwitchingClient: UsageLoading {
    private(set) var calls = 0
    func fetch(account: Account) async throws -> UsageSnapshot {
        self.calls += 1
        let count = self.calls
        if count == 2 {
            // An uncooperative old request may still complete after cancellation.
            try? await Task.sleep(for: .milliseconds(100))
        }
        return try UsageSnapshot.decode(Fixture.usage, email: count >= 3 ? "new@example.com" : "old@example.com")
    }
}
