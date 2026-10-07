import Foundation
import Observation

public struct AccountStatus: Sendable {
    public var snapshot: UsageSnapshot?
    public var error: String?
    public var isRefreshing = false

    public init() {}
}

@MainActor @Observable
public final class RefreshController {
    public private(set) var statuses: [UUID: AccountStatus] = [:]
    public private(set) var isRefreshing = false
    @ObservationIgnored private var active: Task<Void, Never>?
    @ObservationIgnored private let client: any UsageLoading
    @ObservationIgnored private var generation = 0

    public init(client: any UsageLoading) { self.client = client }

    /// Coalesce timer, wake and manual requests instead of accumulating tasks or snapshots.
    @discardableResult
    public func refresh(_ accounts: [Account]) -> Task<Void, Never> {
        if let active { return active }
        let generation = self.generation
        self.isRefreshing = true
        let task = Task { [weak self, client] in
            for account in accounts {
                guard !Task.isCancelled else { break }
                guard self?.generation == generation else { break }
                self?.statuses[account.id, default: AccountStatus()].isRefreshing = true
                do {
                    let snapshot = try await client.fetch(account: account)
                    guard !Task.isCancelled, self?.generation == generation else { break }
                    var status = AccountStatus()
                    status.snapshot = snapshot
                    self?.statuses[account.id] = status
                } catch {
                    guard !Task.isCancelled, self?.generation == generation else { break }
                    self?.statuses[account.id, default: AccountStatus()].error = error.localizedDescription
                    self?.statuses[account.id]?.isRefreshing = false
                }
            }
            guard self?.generation == generation else { return }
            self?.isRefreshing = false
            self?.active = nil
        }
        self.active = task
        return task
    }

    /// Await cancellation before starting a new refresh, including before deleting an owned home.
    public func stop() async {
        self.generation += 1
        let active = self.active
        active?.cancel()
        await active?.value
        self.active = nil
        self.isRefreshing = false
        for id in self.statuses.keys {
            self.statuses[id]?.isRefreshing = false
        }
    }

    public func retainAccounts(_ accounts: [Account]) {
        let ids = Set(accounts.map(\.id))
        self.statuses = self.statuses.filter { ids.contains($0.key) }
    }
}
