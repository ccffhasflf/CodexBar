import Foundation

public struct QuotaWindow: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let usedPercent: Double
    public let resetsAt: Date?
    public let durationSeconds: Int?

    public var remainingPercent: Double {
        max(0, min(100, 100 - self.usedPercent))
    }

    public var roundedRemaining: Int {
        Int(self.remainingPercent.rounded())
    }

    public func resetLabel(now: Date = Date()) -> String {
        guard let resetsAt else { return "重置时间未知" }
        let seconds = resetsAt.timeIntervalSince(now)
        guard seconds > 0 else { return "重置时间已到，等待刷新" }
        let minutes = Int(ceil(seconds / 60))
        if minutes >= 1440 { return "\(minutes / 1440)天 \(minutes % 1440 / 60)小时后重置" }
        if minutes >= 60 { return "\(minutes / 60)小时 \(minutes % 60)分钟后重置" }
        return "\(minutes)分钟后重置"
    }
}

public struct UsageSnapshot: Equatable, Sendable {
    public let email: String?
    public let plan: String?
    public let accountID: String?
    public let windows: [QuotaWindow]
    public let updatedAt: Date

    public var menuWindow: QuotaWindow? {
        // A fully exhausted weekly cap binds even if the short window still has room.
        self.windows.first(where: { ["session", "weekly", "monthly"].contains($0.id) && $0.remainingPercent == 0 })
            ?? self.windows.first(where: { $0.id == "session" })
            ?? self.windows.first
    }

    public static func decode(_ data: Data, email: String?, now: Date = Date()) throws -> Self {
        let response = try JSONDecoder().decode(CodexUsageResponse.self, from: data)
        var windows: [QuotaWindow] = []
        var ids = Set<String>()
        func append(_ raw: CodexUsageResponse.WindowSnapshot?, prefix: String?, position: Int) {
            guard let raw else { return }
            let role: String
            let title: String
            switch raw.limitWindowSeconds {
            case 18000: role = "session"; title = "5 小时额度"
            case 604_800: role = "weekly"; title = "每周额度"
            default:
                role = "window-\(position)"
                title = raw.limitWindowSeconds > 0 ? "\(raw.limitWindowSeconds / 3600) 小时额度" : "额度"
            }
            let id = prefix.map { "\($0)-\(role)" } ?? role
            guard ids.insert(id).inserted else { return }
            windows.append(QuotaWindow(
                id: id,
                title: prefix.map { "\($0) · \(title)" } ?? title,
                usedPercent: Double(max(0, min(100, raw.usedPercent))),
                resetsAt: raw.resetAt > 0 ? Date(timeIntervalSince1970: Double(raw.resetAt)) : nil,
                durationSeconds: raw.limitWindowSeconds > 0 ? raw.limitWindowSeconds : nil))
        }
        append(response.rateLimit?.primaryWindow, prefix: nil, position: 0)
        append(response.rateLimit?.secondaryWindow, prefix: nil, position: 1)
        windows.sort { ($0.durationSeconds ?? Int.max) < ($1.durationSeconds ?? Int.max) }
        if let cap = response.resolvedIndividualLimit {
            let percent: Double? = if let remaining = cap.remainingPercent, remaining.isFinite {
                100 - remaining
            } else if let limit = cap.limit, let used = cap.used, limit > 0, limit.isFinite, used.isFinite {
                used / limit * 100
            } else {
                nil
            }
            if let percent, percent.isFinite {
                windows.append(QuotaWindow(
                    id: "monthly",
                    title: "月度额度",
                    usedPercent: max(0, min(100, percent)),
                    resetsAt: cap.resetsAt.flatMap { $0 > 0 ? Date(timeIntervalSince1970: Double($0)) : nil },
                    durationSeconds: nil))
            }
        }
        for (index, extra) in (response.additionalRateLimits ?? []).enumerated() {
            let title = extra.limitName ?? extra.meteredFeature ?? "额外额度 \(index + 1)"
            append(extra.rateLimit?.primaryWindow, prefix: title, position: 0)
            append(extra.rateLimit?.secondaryWindow, prefix: title, position: 1)
        }
        guard !windows.isEmpty else { throw LiteError.noQuota }
        return Self(
            email: email,
            plan: response.planType?.rawValue,
            accountID: response.accountId,
            windows: windows,
            updatedAt: now)
    }
}

public enum LiteError: LocalizedError, Sendable {
    case missingCredentials
    case invalidCredentials
    case apiKeyAccount
    case loginRequired
    case noQuota
    case accountMismatch
    case http(Int)
    case invalidResponse
    case missingCLI
    case loginFailed
    case loginTimedOut
    case invalidConfiguration

    public var errorDescription: String? {
        switch self {
        case .missingCredentials: "未找到 auth.json，请先在 Codex 中登录，或在设置中选择正确的登录目录。"
        case .invalidCredentials: "登录文件无效，请重新登录这个账号。"
        case .apiKeyAccount: "API Key 登录没有订阅额度，请使用 ChatGPT 账号登录。"
        case .loginRequired: "登录已过期或被撤销，请重新登录这个账号。"
        case .noQuota: "接口未返回可用的额度窗口，暂时无法显示额度。"
        case .accountMismatch: "返回的账号与所选账号不一致，请重新登录。"
        case let .http(status): "额度请求失败（HTTP \(status)），请稍后刷新。"
        case .invalidResponse: "服务返回了无效数据。"
        case .missingCLI: "未找到 Codex CLI。请在设置中选择 Codex 可执行文件。"
        case .loginFailed: "Codex 登录未完成，请重试。"
        case .loginTimedOut: "登录等待超时，请重试。"
        case .invalidConfiguration: "配置文件无效。为保留账号信息，未覆盖原文件。"
        }
    }
}
