import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct CodexUsageResponse: Decodable, Sendable {
    public let accountId: String?
    public let planType: PlanType?
    public let rateLimit: RateLimitDetails?
    public let individualLimit: SpendControlLimitSnapshot?
    /// Team/enterprise workspaces report the monthly credit pool here instead of at the response root.
    /// Kept separate from `individualLimit` so the established root → `rate_limit` precedence is preserved;
    /// consumers select this only when both of those are absent.
    public let spendControlIndividualLimit: SpendControlLimitSnapshot?
    public let spendControlPresent: Bool
    /// Model-specific limits (e.g. GPT-5.3-Codex-Spark) that sit alongside the primary/weekly windows.
    public let additionalRateLimits: [AdditionalRateLimit]?
    let additionalRateLimitsDecodeFailed: Bool

    enum CodingKeys: String, CodingKey {
        case accountId = "account_id"
        case accountIdCamel = "accountId"
        case planType = "plan_type"
        case rateLimit = "rate_limit"
        case individualLimit = "individual_limit"
        case individualLimitCamel = "individualLimit"
        case spendControl = "spend_control"
        case spendControlCamel = "spendControl"
        case additionalRateLimits = "additional_rate_limits"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.accountId = (try? container.decodeIfPresent(String.self, forKey: .accountId))
            ?? (try? container.decodeIfPresent(String.self, forKey: .accountIdCamel))
        self.planType = try? container.decodeIfPresent(PlanType.self, forKey: .planType)
        self.rateLimit = try? container.decodeIfPresent(RateLimitDetails.self, forKey: .rateLimit)
        self.individualLimit = (try? container.decodeIfPresent(
            SpendControlLimitSnapshot.self,
            forKey: .individualLimit))
            ?? (try? container.decodeIfPresent(SpendControlLimitSnapshot.self, forKey: .individualLimitCamel))
        self.spendControlIndividualLimit = Self.decodeSpendControlIndividualLimit(container: container)
        self.spendControlPresent = container.contains(.spendControl) || container.contains(.spendControlCamel)
        // Optional and additive: missing/malformed extra limits must never disturb primary/weekly mapping.
        // Decode per element so a single malformed entry cannot discard its valid siblings; a non-array
        // value (or absent field) leaves `additionalRateLimits` nil and primary/weekly mapping untouched.
        let additionalRateLimitsHadValue = Self.hasNonNilValue(container: container, key: .additionalRateLimits)
        do {
            let decoded = try container.decodeIfPresent(
                [LossyAdditionalRateLimit].self,
                forKey: .additionalRateLimits)
            self.additionalRateLimits = decoded?.compactMap(\.value)
            self.additionalRateLimitsDecodeFailed = decoded?.contains(where: \.decodeFailed) == true
                || self.additionalRateLimits?.contains(where: \.hasWindowDecodeFailure) == true
        } catch {
            self.additionalRateLimits = nil
            self.additionalRateLimitsDecodeFailed = additionalRateLimitsHadValue
        }
    }

    private static func hasNonNilValue(
        container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys) -> Bool
    {
        guard container.contains(key) else { return false }
        return (try? container.decodeNil(forKey: key)) == false
    }

    /// Credit-limit source precedence: response root, then `rate_limit`, then `spend_control`.
    public var resolvedIndividualLimit: SpendControlLimitSnapshot? {
        self.individualLimit ?? self.rateLimit?.individualLimit ?? self.spendControlIndividualLimit
    }

    private static func decodeSpendControlIndividualLimit(
        container: KeyedDecodingContainer<CodingKeys>) -> SpendControlLimitSnapshot?
    {
        let details = (try? container.decodeIfPresent(SpendControlDetails.self, forKey: .spendControl))
            ?? (try? container.decodeIfPresent(SpendControlDetails.self, forKey: .spendControlCamel))
        return details?.individualLimit
    }

    /// `spend_control` wrapper from `wham/usage`; only the individual limit is consumed today.
    public struct SpendControlDetails: Decodable, Sendable {
        public let individualLimit: SpendControlLimitSnapshot?

        enum CodingKeys: String, CodingKey {
            case individualLimit = "individual_limit"
            case individualLimitCamel = "individualLimit"
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.individualLimit = (try? container.decodeIfPresent(
                SpendControlLimitSnapshot.self,
                forKey: .individualLimit))
                ?? (try? container.decodeIfPresent(SpendControlLimitSnapshot.self, forKey: .individualLimitCamel))
        }
    }

    public enum PlanType: Sendable, Decodable, Equatable {
        case guest
        case free
        case go
        case plus
        case pro
        case freeWorkspace
        case team
        case business
        case education
        case quorum
        case k12
        case enterprise
        case edu
        case unknown(String)

        public var rawValue: String {
            switch self {
            case .guest: "guest"
            case .free: "free"
            case .go: "go"
            case .plus: "plus"
            case .pro: "pro"
            case .freeWorkspace: "free_workspace"
            case .team: "team"
            case .business: "business"
            case .education: "education"
            case .quorum: "quorum"
            case .k12: "k12"
            case .enterprise: "enterprise"
            case .edu: "edu"
            case let .unknown(value): value
            }
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            switch value {
            case "guest": self = .guest
            case "free": self = .free
            case "go": self = .go
            case "plus": self = .plus
            case "pro": self = .pro
            case "free_workspace": self = .freeWorkspace
            case "team": self = .team
            case "business": self = .business
            case "education": self = .education
            case "quorum": self = .quorum
            case "k12": self = .k12
            case "enterprise": self = .enterprise
            case "edu": self = .edu
            default:
                self = .unknown(value)
            }
        }
    }

    public struct RateLimitDetails: Decodable, Sendable {
        public let primaryWindow: WindowSnapshot?
        public let secondaryWindow: WindowSnapshot?
        public let individualLimit: SpendControlLimitSnapshot?
        let primaryWindowDecodeFailed: Bool
        let secondaryWindowDecodeFailed: Bool

        enum CodingKeys: String, CodingKey {
            case primaryWindow = "primary_window"
            case secondaryWindow = "secondary_window"
            case individualLimit = "individual_limit"
            case individualLimitCamel = "individualLimit"
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let primaryHadValue = Self.hasNonNilValue(container: container, key: .primaryWindow)
            do {
                self.primaryWindow = try container.decodeIfPresent(WindowSnapshot.self, forKey: .primaryWindow)
                self.primaryWindowDecodeFailed = false
            } catch {
                self.primaryWindow = nil
                self.primaryWindowDecodeFailed = primaryHadValue
            }

            let secondaryHadValue = Self.hasNonNilValue(container: container, key: .secondaryWindow)
            do {
                self.secondaryWindow = try container.decodeIfPresent(WindowSnapshot.self, forKey: .secondaryWindow)
                self.secondaryWindowDecodeFailed = false
            } catch {
                self.secondaryWindow = nil
                self.secondaryWindowDecodeFailed = secondaryHadValue
            }
            self.individualLimit = (try? container.decodeIfPresent(
                SpendControlLimitSnapshot.self,
                forKey: .individualLimit))
                ?? (try? container.decodeIfPresent(SpendControlLimitSnapshot.self, forKey: .individualLimitCamel))
        }

        private static func hasNonNilValue(
            container: KeyedDecodingContainer<CodingKeys>,
            key: CodingKeys) -> Bool
        {
            guard container.contains(key) else { return false }
            return (try? container.decodeNil(forKey: key)) == false
        }

        var hasWindowDecodeFailure: Bool {
            self.primaryWindowDecodeFailed || self.secondaryWindowDecodeFailed
        }
    }

    public struct WindowSnapshot: Decodable, Sendable {
        public let usedPercent: Int
        public let resetAt: Int
        public let limitWindowSeconds: Int

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case resetAt = "reset_at"
            case limitWindowSeconds = "limit_window_seconds"
        }
    }

    /// One entry of `additional_rate_limits`: a named, model-specific limit (e.g. GPT-5.3-Codex-Spark)
    /// whose windows reuse the same shape as the primary/weekly `RateLimitDetails`.
    public struct AdditionalRateLimit: Decodable, Sendable {
        public let limitName: String?
        public let meteredFeature: String?
        public let rateLimit: RateLimitDetails?
        let rateLimitDecodeFailed: Bool

        enum CodingKeys: String, CodingKey {
            case limitName = "limit_name"
            case meteredFeature = "metered_feature"
            case rateLimit = "rate_limit"
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.limitName = try? container.decodeIfPresent(String.self, forKey: .limitName)
            self.meteredFeature = try? container.decodeIfPresent(String.self, forKey: .meteredFeature)
            let rateLimitHadValue = Self.hasNonNilValue(container: container, key: .rateLimit)
            do {
                self.rateLimit = try container.decodeIfPresent(RateLimitDetails.self, forKey: .rateLimit)
                self.rateLimitDecodeFailed = false
            } catch {
                self.rateLimit = nil
                self.rateLimitDecodeFailed = rateLimitHadValue
            }
        }

        private static func hasNonNilValue(
            container: KeyedDecodingContainer<CodingKeys>,
            key: CodingKeys) -> Bool
        {
            guard container.contains(key) else { return false }
            return (try? container.decodeNil(forKey: key)) == false
        }

        var hasWindowDecodeFailure: Bool {
            self.rateLimitDecodeFailed || self.rateLimit?.hasWindowDecodeFailure == true
        }
    }

    /// Decodes a single `additional_rate_limits` element without ever throwing, so one malformed
    /// entry cannot discard its valid siblings during array decoding.
    private struct LossyAdditionalRateLimit: Decodable {
        let value: AdditionalRateLimit?
        let decodeFailed: Bool

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            self.value = try? container.decode(AdditionalRateLimit.self)
            self.decodeFailed = self.value == nil
        }
    }

    public struct SpendControlLimitSnapshot: Decodable, Sendable {
        public let limit: Double?
        public let used: Double?
        public let remainingPercent: Double?
        public let resetsAt: Int?

        enum CodingKeys: String, CodingKey {
            case limit
            case used
            case remainingPercent
            case remainingPercentSnake = "remaining_percent"
            case resetsAt
            case resetsAtSnake = "resets_at"
            case resetAtSnake = "reset_at"
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.limit = CodexSpendControlNumber.double(container, forKey: .limit)
            self.used = CodexSpendControlNumber.double(container, forKey: .used)
            self.remainingPercent = CodexSpendControlNumber.double(container, forKey: .remainingPercent)
                ?? CodexSpendControlNumber.double(container, forKey: .remainingPercentSnake)
            // `wham/usage` spells this `reset_at` (matching `WindowSnapshot`), other shapes use `resets_at`.
            self.resetsAt = CodexSpendControlNumber.integer(container, forKey: .resetsAt)
                ?? CodexSpendControlNumber.integer(container, forKey: .resetsAtSnake)
                ?? CodexSpendControlNumber.integer(container, forKey: .resetAtSnake)
        }
    }
}
