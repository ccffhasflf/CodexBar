// Upstream CodexBar RateWindow data contract (MIT).
import Foundation

public struct RateWindow: Codable, Equatable, Sendable {
    /// Provider usage value, intentionally not normalized globally. Pace and provider-specific diagnostics may
    /// preserve raw over-quota values; display-only projections should use `UsagePercent.displayClamped`.
    public let usedPercent: Double
    public let windowMinutes: Int?
    public let resetsAt: Date?
    /// Optional textual reset description (used by Claude CLI UI scrape).
    public let resetDescription: String?
    /// Optional percent restored on the next regeneration tick for providers with rolling recovery.
    public let nextRegenPercent: Double?
    /// Whether this window was synthesized to stand in for a quota lane the provider did not actually
    /// report, rather than being a real zero-usage window.
    ///
    /// Claude web returns a `0%` five-hour window when `five_hour` is `null` (an account with no live
    /// session but a real weekly lane). Lane classifiers — e.g. the combined "Session + Weekly" menu-bar
    /// metric — must treat such a window as "no session lane present" instead of surfacing a phantom
    /// `5h 0%`/`5h 100%` session. A genuine session, even one freshly reset to 0%, is NOT a placeholder.
    /// Missing values decode as `false` for older cached payloads.
    public let isSyntheticPlaceholder: Bool

    public init(
        usedPercent: Double,
        windowMinutes: Int?,
        resetsAt: Date?,
        resetDescription: String?,
        nextRegenPercent: Double? = nil,
        isSyntheticPlaceholder: Bool = false)
    {
        self.usedPercent = usedPercent
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
        self.resetDescription = resetDescription
        self.nextRegenPercent = nextRegenPercent
        self.isSyntheticPlaceholder = isSyntheticPlaceholder
    }

    private enum CodingKeys: String, CodingKey {
        case usedPercent
        case windowMinutes
        case resetsAt
        case resetDescription
        case nextRegenPercent
        case isSyntheticPlaceholder
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.usedPercent = try container.decode(Double.self, forKey: .usedPercent)
        self.windowMinutes = try container.decodeIfPresent(Int.self, forKey: .windowMinutes)
        self.resetsAt = try container.decodeIfPresent(Date.self, forKey: .resetsAt)
        self.resetDescription = try container.decodeIfPresent(String.self, forKey: .resetDescription)
        self.nextRegenPercent = try container.decodeIfPresent(Double.self, forKey: .nextRegenPercent)
        self.isSyntheticPlaceholder =
            try container.decodeIfPresent(Bool.self, forKey: .isSyntheticPlaceholder) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.usedPercent, forKey: .usedPercent)
        try container.encodeIfPresent(self.windowMinutes, forKey: .windowMinutes)
        try container.encodeIfPresent(self.resetsAt, forKey: .resetsAt)
        try container.encodeIfPresent(self.resetDescription, forKey: .resetDescription)
        try container.encodeIfPresent(self.nextRegenPercent, forKey: .nextRegenPercent)
        // Only persist the flag when set, keeping payloads identical for the common (real-window) case.
        if self.isSyntheticPlaceholder {
            try container.encode(true, forKey: .isSyntheticPlaceholder)
        }
    }

    /// A synthetic placeholder has no measured quota value, even when its stored percent is zero.
    public var measured: Self? {
        self.isSyntheticPlaceholder ? nil : self
    }

    public var remainingPercent: Double {
        max(0, 100 - self.usedPercent)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
