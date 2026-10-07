// Codex-only reset credit models adapted from upstream CreditsModels.swift (MIT).
import Foundation

public struct CodexRateLimitResetCreditsSnapshot: Equatable, Codable, Sendable {
    public let credits: [CodexRateLimitResetCredit]
    public let availableCount: Int
    public let updatedAt: Date

    public init(credits: [CodexRateLimitResetCredit], availableCount: Int, updatedAt: Date) {
        self.credits = credits
        self.availableCount = availableCount
        self.updatedAt = updatedAt
    }

    public var nextExpiringAvailableCredit: CodexRateLimitResetCredit? {
        self.availableInventory(at: self.updatedAt).nextExpiringCredit
    }

    public func availableInventory(at date: Date) -> CodexRateLimitResetCreditInventory {
        CodexRateLimitResetCreditInventory(credits: self.credits, at: date)
    }

    public func availableCredits(at date: Date) -> [CodexRateLimitResetCredit] {
        self.availableInventory(at: date).credits
    }
}

public struct CodexRateLimitResetCreditInventory: Equatable, Sendable {
    public let credits: [CodexRateLimitResetCredit]

    public var count: Int {
        self.credits.count
    }

    public var nextExpiringCredit: CodexRateLimitResetCredit? {
        self.credits.first { $0.expiresAt != nil }
    }

    public init(credits: [CodexRateLimitResetCredit], at date: Date) {
        self.credits = credits
            .filter { credit in
                credit.status == .available && (credit.expiresAt.map { $0 > date } ?? true)
            }
            .sorted { lhs, rhs in
                switch (lhs.expiresAt, rhs.expiresAt) {
                case let (lhsDate?, rhsDate?):
                    if lhsDate != rhsDate { return lhsDate < rhsDate }
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    break
                }
                return lhs.id < rhs.id
            }
    }
}

public struct CodexRateLimitResetCredit: Equatable, Codable, Sendable, Identifiable {
    public let id: String
    public let resetType: String
    public let status: CodexRateLimitResetCreditStatus
    public let grantedAt: Date
    public let expiresAt: Date?
    public let redeemStartedAt: Date?
    public let redeemedAt: Date?
    public let title: String?
    public let description: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case resetType = "reset_type"
        case status
        case grantedAt = "granted_at"
        case expiresAt = "expires_at"
        case redeemStartedAt = "redeem_started_at"
        case redeemedAt = "redeemed_at"
        case title
        case description
    }

    public init(
        id: String,
        resetType: String,
        status: CodexRateLimitResetCreditStatus,
        grantedAt: Date,
        expiresAt: Date?,
        redeemStartedAt: Date?,
        redeemedAt: Date?,
        title: String?,
        description: String?)
    {
        self.id = id
        self.resetType = resetType
        self.status = status
        self.grantedAt = grantedAt
        self.expiresAt = expiresAt
        self.redeemStartedAt = redeemStartedAt
        self.redeemedAt = redeemedAt
        self.title = title
        self.description = description
    }
}

public enum CodexRateLimitResetCreditStatus: Equatable, Codable, Sendable {
    case available
    case redeeming
    case redeemed
    case expired
    case unknown(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        switch value {
        case "available":
            self = .available
        case "redeeming":
            self = .redeeming
        case "redeemed":
            self = .redeemed
        case "expired":
            self = .expired
        default:
            self = .unknown(value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.rawValue)
    }

    public var rawValue: String {
        switch self {
        case .available:
            "available"
        case .redeeming:
            "redeeming"
        case .redeemed:
            "redeemed"
        case .expired:
            "expired"
        case let .unknown(value):
            value
        }
    }
}
