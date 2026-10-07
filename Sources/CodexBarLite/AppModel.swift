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
        var snapshot = try UsageSnapshot.decode(Data(response.utf8), email: "preview@example.com")
        let now = snapshot.updatedAt
        snapshot.resetCredits = CodexRateLimitResetCreditsSnapshot(
            credits: [CodexRateLimitResetCredit(
                id: "demo-reset-credit",
                resetType: "weekly",
                status: .available,
                grantedAt: now,
                expiresAt: now.addingTimeInterval(86400),
                redeemStartedAt: nil,
                redeemedAt: nil,
                title: nil,
                description: nil)],
            availableCount: 1,
            updatedAt: now)
        return snapshot
    }
}

@MainActor @Observable
final class AppModel {
    private(set) var configuration: Configuration
    private(set) var currentAccount: Account
    let refresh: RefreshController
    var notice: String?
    var launchAtLogin = SMAppService.mainApp.status == .enabled
    let isDemo: Bool
    @ObservationIgnored private let repository: AccountRepository
    @ObservationIgnored private let defaultHome: URL
    @ObservationIgnored private var timerTask: Task<Void, Never>?
    @ObservationIgnored private var followTask: Task<Void, Never>?
    @ObservationIgnored private var monitor: CurrentLoginMonitor?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private var sleepObserver: NSObjectProtocol?
    @ObservationIgnored private var sleeping = false
    @ObservationIgnored private var stopped = false
    @ObservationIgnored private var started = false

    init(
        repository: AccountRepository = .standard,
        demo: Bool = false,
        defaultHome: URL = CurrentCodexHome.resolve(configured: nil),
        client: (any UsageLoading)? = nil) throws
    {
        self.repository = repository
        self.isDemo = demo
        self.defaultHome = defaultHome
        let configuration = demo ? Configuration() : try repository.load()
        self.configuration = configuration
        let home = configuration.codexHome.map { URL(fileURLWithPath: $0) } ?? defaultHome
        self.currentAccount = Account(name: "当前 Codex 登录", externalHome: home.path)
        self.refresh = RefreshController(client: client ?? (demo
                ? DemoUsageClient() : UsageClient(repository: repository)))
    }

    var currentHome: URL {
        URL(fileURLWithPath: self.currentAccount.externalHome!, isDirectory: true)
    }

    var status: AccountStatus? {
        self.refresh.statuses[self.currentAccount.id]
    }

    var menuTitle: String {
        guard self.status?.error == nil, let window = self.status?.snapshot?.menuWindow else { return "Codex —" }
        let suffix = self.isDemo ? " · 演示" : ""
        return "Codex \(window.roundedRemaining)%\(suffix)"
    }

    func start() {
        guard !self.started else { return }
        self.started = true
        self.startMonitor()
        self.refreshNow()
        self.schedule()
        self.wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main)
        { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.sleeping = false
                self.followCurrentLogin()
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
        self.followTask?.cancel()
        self.monitor?.stop()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
        Task { await self.refresh.stop() }
    }

    func refreshNow() {
        guard self.followTask == nil, !self.sleeping, !self.stopped else { return }
        self.refresh.refresh([self.currentAccount])
    }

    private func startMonitor() {
        self.monitor?.stop()
        guard !self.isDemo else { return }
        self.monitor = CurrentLoginMonitor(home: self.currentHome) { [weak self] in
            self?.followCurrentLogin()
        }
        self.monitor?.start()
    }

    /// Give each credential revision a new display identity. Never show the previous account's
    /// quota while its cancelled request is draining or the replacement account is loading.
    func followCurrentLogin() {
        guard !self.stopped else { return }
        self.followTask?.cancel()
        let home = self.configuration.codexHome.map { URL(fileURLWithPath: $0) } ?? self.defaultHome
        let account = Account(name: "当前 Codex 登录", externalHome: home.path)
        self.currentAccount = account
        self.refresh.retainAccounts([])
        self.followTask = Task { [weak self] in
            guard let self else { return }
            await self.refresh.stop()
            guard !Task.isCancelled, self.currentAccount.id == account.id else { return }
            self.followTask = nil
            self.refreshNow()
        }
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

    func setInterval(_ minutes: Int) {
        guard [1, 5, 15, 30].contains(minutes) else { return }
        var config = self.configuration
        config.refreshMinutes = minutes
        do { try self.persist(config); self.schedule() } catch { self.notice = error.localizedDescription }
    }

    func setResetTimeDisplayStyle(_ style: ResetTimeDisplayStyle) {
        var config = self.configuration
        config.resetTimeDisplayStyle = style
        do { try self.persist(config) } catch { self.notice = error.localizedDescription }
    }

    func setHome(_ home: URL?) {
        var config = self.configuration
        config.codexHome = home?.standardizedFileURL.path
        do {
            try self.persist(config)
            self.followCurrentLogin()
            self.startMonitor()
        } catch { self.notice = error.localizedDescription }
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
}
