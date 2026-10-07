import CodexBarLiteCore
import Foundation

/// Codex-only adapter for upstream MenuCardView+ModelHelpers' paceDetail and metric construction.
enum QuotaPresentation {
    static func metric(
        window: QuotaWindow, now: Date, resetStyle: ResetTimeDisplayStyle = .countdown) -> UsageMetric
    {
        let rate = RateWindow(
            usedPercent: window.usedPercent,
            windowMinutes: window.durationSeconds.map { $0 / 60 },
            resetsAt: window.resetsAt,
            resetDescription: nil)
        let detail: UsagePaceText.WeeklyDetail? = if rate.windowMinutes == 10080 {
            if let pace = UsagePace.weekly(window: rate, now: now),
               pace.expectedUsedPercent >= 3 || pace.etaSeconds == 0,
               rate.remainingPercent > 0
            {
                UsagePaceText.weeklyDetail(pace: pace, now: now)
            } else {
                nil
            }
        } else if window.id != "monthly" {
            UsagePaceText.sessionDetail(window: rate, now: now)
        } else {
            nil
        }
        let resetText = UsageFormatter.resetLine(for: rate, style: resetStyle, now: now)
        let title: String = switch window.id {
        case "session": L("Session")
        case "weekly": L("Weekly")
        case "monthly": L("Monthly")
        default: window.title
        }
        return UsageMetric(
            id: window.id,
            title: title,
            percent: window.remainingPercent,
            percentStyle: .left,
            resetText: resetText,
            detailText: nil,
            detailLeftText: detail?.leftLabel,
            detailRightText: detail?.rightLabel,
            pacePercent: detail.flatMap { $0.stage == .onTrack ? nil : 100 - $0.expectedUsedPercent },
            detailIsPaceDerived: detail != nil,
            paceOnTop: detail.map { rate.usedPercent <= $0.expectedUsedPercent } ?? true)
    }
}
