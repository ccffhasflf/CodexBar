import AppKit
import CodexBarLiteCore
import Observation
import ServiceManagement

struct DemoUsageClient: UsageLoading {
    func fetch(account: Account) async throws -> UsageSnapshot {
        let response = """
        {"plan_type":"plus","rate_limit":{
          "primary_window":{"used_percent":28,
            "reset_at":\(Int(Date().timeIntervalSince1970) + 10800),"limit_window_seconds":18000},
          "secondary_window":{"used_percent":46,
            "reset_at":\(Int(Date().timeIntervalSince1970) + 259_200),"limit_window_seconds":604800}}}
        """
        return try UsageSnapshot.decode(Data(response.utf8), email: "preview@example.com")
    }
}

@MainActor @Observable
final class AppModel {
    private(set) var configuration: Configuration
    let refresh: RefreshController
    let login = LoginCoordinator()
    var notice: String?
    var isEditingAccounts = false
    var launchAtLogin = SMAppService.mainApp.status == .enabled
    let isDemo: Bool
    @ObservationIgnored private let repository: AccountRepository
    @ObservationIgnored private var timerTask: Task<Void, Never>?
    @ObservationIgnored private var loginTask: Task<Void, Never>?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private var sleepObserver: NSObjectProtocol?
    @ObservationIgnored private var sleeping = false
    @ObservationIgnored private var stopped = false
    @ObservationIgnored private var started = false

    init(repository: AccountRepository = .standard, demo: Bool = false) throws {
        self.repository = repository
        self.isDemo = demo
        if demo {
            var config = Configuration()
            let account = Account(name: "演示账号")
            config.accounts = [account]
            config.selectedID = account.id
            self.configuration = config
            self.refresh = RefreshController(client: DemoUsageClient())
        } else {
            self.configuration = try repository.load()
            self.refresh = RefreshController(client: UsageClient(repository: repository))
        }
    }

    var selected: Account? {
        self.configuration.accounts.first { $0.id == self.configuration.selectedID }
    }

    var status: AccountStatus? {
        self.selected.flatMap { self.refresh.statuses[$0.id] }
    }

    var menuTitle: String {
        guard self.status?.error == nil, let window = self.status?.snapshot?.menuWindow else { return "Codex —" }
        let suffix = self.isDemo ? " · 演示" : ""
        return "Codex \(window.roundedRemaining)%\(suffix)"
    }

    func start() {
        guard !self.started else { return }
        self.started = true
        self.refreshNow()
        self.schedule()
        self.wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main)
        { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.sleeping = false
                self.refreshNow()
                self.schedule()
            }
        }
        self.sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main)
        { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.sleeping = true
                self.timerTask?.cancel()
                await self.refresh.stop()
            }
        }
    }

    func stop() {
        self.stopped = true
        self.timerTask?.cancel()
        self.loginTask?.cancel()
        self.login.terminateForQuit()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
        Task { await self.refresh.stop() }
    }

    func refreshNow() {
        guard !self.isEditingAccounts, !self.sleeping, !self.stopped else { return }
        self.refresh.refresh(self.configuration.accounts)
    }

    private func schedule() {
        self.timerTask?.cancel()
        let seconds = self.configuration.refreshMinutes * 60
        self.timerTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
                guard let self, !self.sleeping, !self.stopped else { return }
                self.refreshNow()
            }
        }
    }

    private func persist(_ changed: Configuration) throws {
        if !self.isDemo { try self.repository.save(changed) }
        self.configuration = changed
    }

    func select(_ id: UUID) {
        var config = self.configuration
        config.selectedID = id
        do { try self.persist(config) } catch { self.notice = error.localizedDescription }
    }

    func setInterval(_ minutes: Int) {
        guard [1, 5, 15, 30].contains(minutes) else { return }
        var config = self.configuration
        config.refreshMinutes = minutes
        do { try self.persist(config); self.schedule() } catch { self.notice = error.localizedDescription }
    }

    func setCLI(_ path: String) {
        var config = self.configuration
        config.cliPath = path
        do { try self.persist(config) } catch { self.notice = error.localizedDescription }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard !self.isDemo else { return }
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            self.launchAtLogin = SMAppService.mainApp.status == .enabled
            if SMAppService.mainApp.status == .requiresApproval {
                self.notice = "请在系统设置 → 通用 → 登录项中允许 CodexBar Lite。"
            }
        } catch { self.notice = error.localizedDescription }
    }

    func link(home: URL) {
        guard !self.isDemo else { return }
        let path = home.standardizedFileURL.path
        if let existing = self.configuration.accounts.first(where: { $0.externalHome == path }) {
            self.select(existing.id)
            return
        }
        var account = Account(name: "现有 Codex 登录", externalHome: path)
        do {
            account.name = try self.repository.loginLabel(for: account)
            var config = self.configuration
            config.accounts.append(account)
            config.selectedID = account.id
            try self.persist(config)
            self.refreshNow()
        } catch { self.notice = error.localizedDescription }
    }

    func addAccount(replacing old: Account? = nil) {
        guard self.loginTask == nil, !self.isEditingAccounts, !self.isDemo else { return }
        self.notice = nil
        let account = Account(name: "新账号")
        self.loginTask = Task { [weak self] in
            guard let self else { return }
            defer { self.loginTask = nil }
            do {
                try self.repository.prepare(account)
                try await self.login.run(
                    home: self.repository.home(for: account),
                    configured: self.configuration.cliPath)
                var added = account
                added.name = try self.repository.loginLabel(for: account)
                self.isEditingAccounts = true
                await self.refresh.stop()
                defer { self.isEditingAccounts = false }
                var config = self.configuration
                if let old { config.accounts.removeAll { $0.id == old.id } }
                config.accounts.append(added)
                config.selectedID = added.id
                try self.persist(config)
                self.refresh.retainAccounts(config.accounts)
                if let old { try self.repository.removeCredentials(for: old) }
            } catch is CancellationError {
                try? self.repository.removeCredentials(for: account)
            } catch {
                self.notice = error.localizedDescription
                // Never delete credentials after the new account has been committed to config.
                if !self.configuration.accounts.contains(where: { $0.id == account.id }) {
                    try? self.repository.removeCredentials(for: account)
                }
            }
            self.refreshNow()
        }
    }

    func rename(_ account: Account, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var config = self.configuration
        guard let index = config.accounts.firstIndex(where: { $0.id == account.id }) else { return }
        config.accounts[index].name = name
        do { try self.persist(config) } catch { self.notice = error.localizedDescription }
    }

    func remove(_ account: Account) async {
        guard !self.isEditingAccounts, !self.login.isRunning else { return }
        self.isEditingAccounts = true
        await self.refresh.stop()
        defer { self.isEditingAccounts = false; self.refreshNow() }
        var config = self.configuration
        config.accounts.removeAll { $0.id == account.id }
        if config.selectedID == account.id { config.selectedID = config.accounts.first?.id }
        do {
            try self.persist(config)
            self.refresh.retainAccounts(config.accounts)
            if !self.isDemo { try self.repository.removeCredentials(for: account) }
        } catch { self.notice = error.localizedDescription }
    }
}
