import Foundation
import Testing
@testable import CodexBarLiteCore

private actor ControlledClient: UsageLoading {
    private(set) var calls = 0
    var failing = false
    let delay: Duration

    init(delay: Duration = .zero) { self.delay = delay }
    func fail() { self.failing = true }

    func fetch(account: Account) async throws -> UsageSnapshot {
        self.calls += 1
        try await Task.sleep(for: self.delay)
        if self.failing { throw LiteError.http(503) }
        return try UsageSnapshot.decode(Fixture.usage, email: nil)
    }
}

@MainActor
struct RefreshTests {
    @Test func `overlapping refresh requests are coalesced`() async {
        let client = ControlledClient(delay: .milliseconds(30))
        let controller = RefreshController(client: client)
        let accounts = [Account(name: "A"), Account(name: "B")]
        let first = controller.refresh(accounts)
        for _ in 0..<100 {
            controller.refresh(accounts)
        }
        await first.value
        #expect(await client.calls == 2)
        #expect(controller.statuses.count == 2)
        #expect(!controller.isRefreshing)
    }

    @Test func `failed refresh preserves last snapshot with an explicit error`() async {
        let client = ControlledClient()
        let controller = RefreshController(client: client)
        let account = Account(name: "A")
        await controller.refresh([account]).value
        let original = controller.statuses[account.id]?.snapshot
        await client.fail()
        await controller.refresh([account]).value
        #expect(controller.statuses[account.id]?.snapshot == original)
        #expect(controller.statuses[account.id]?.error != nil)
    }

    @Test func `cancellation prevents late publication and allows the next refresh`() async {
        let client = ControlledClient(delay: .milliseconds(30))
        let controller = RefreshController(client: client)
        let account = Account(name: "A")
        controller.refresh([account])
        await controller.stop()
        #expect(controller.statuses[account.id]?.snapshot == nil)
        await controller.refresh([account]).value
        #expect(controller.statuses[account.id]?.snapshot != nil)
    }

    @Test func `ten thousand refreshes retain only latest account snapshots`() async {
        let client = ControlledClient()
        let controller = RefreshController(client: client)
        let accounts = [Account(name: "A"), Account(name: "B")]
        for _ in 0..<10000 {
            await controller.refresh(accounts).value
        }
        #expect(controller.statuses.count == 2)
        #expect(await client.calls == 20000)
        controller.retainAccounts([accounts[0]])
        #expect(controller.statuses.count == 1)
        #expect(controller.statuses[accounts[1].id] == nil)
    }
}
