import Foundation
import Testing
@testable import CodexBarLite
@testable import CodexBarLiteCore

struct PacePresentationTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func window(id: String = "weekly", used: Double, elapsed: Double = 0.5) -> QuotaWindow {
        let duration = id == "weekly" ? 604_800 : 18000
        return QuotaWindow(
            id: id,
            title: id,
            usedPercent: used,
            resetsAt: self.now.addingTimeInterval(Double(duration) * (1 - elapsed)),
            durationSeconds: duration)
    }

    @Test func `reserve uses upstream headroom hint and expected remaining marker`() {
        let metric = QuotaPresentation.metric(window: self.window(used: 25), now: self.now)
        #expect(metric.detailLeftText == "余量 25%")
        #expect(metric.detailRightText == "持续到重置 · 1.5 倍余量")
        #expect(metric.pacePercent == 50)
        #expect(metric.paceOnTop)
        #expect(metric.linePresentation(title: "每周").titleText == "每周 75% 剩余")
    }

    @Test func `session deficit uses original projected exhaustion calculation`() {
        let metric = QuotaPresentation.metric(window: self.window(id: "session", used: 75), now: self.now)
        #expect(metric.detailLeftText == "超额 25%")
        #expect(metric.detailRightText == "预计 50m 后耗尽")
        #expect(metric.pacePercent == 50)
        #expect(!metric.paceOnTop)
    }

    @Test func `on pace hides stripe but retains original description`() {
        let metric = QuotaPresentation.metric(window: self.window(used: 50), now: self.now)
        #expect(metric.detailLeftText == "节奏正常")
        #expect(metric.detailRightText == "持续到重置")
        #expect(metric.pacePercent == nil)
    }

    @Test func `new expired missing and exhausted windows do not invent a forecast`() {
        for window in [
            self.window(used: 1, elapsed: 0.01),
            self.window(used: 100),
            self.window(used: 20, elapsed: 1.1),
            QuotaWindow(id: "session", title: "session", usedPercent: 20, resetsAt: nil, durationSeconds: 18000),
        ] {
            let metric = QuotaPresentation.metric(window: window, now: self.now)
            #expect(metric.detailRightText == nil)
            #expect(metric.pacePercent == nil)
        }
    }

    @Test func `original weekly exhaustion policy caps session icon until reset`() {
        let values = CodexStatusIcon.values(windows: [
            self.window(id: "session", used: 28), self.window(used: 100),
        ], now: self.now)
        #expect(values.primary == 0)
        #expect(values.secondary == 0)
        let expired = CodexStatusIcon.values(windows: [
            self.window(id: "session", used: 28), self.window(used: 100, elapsed: 1.1),
        ], now: self.now)
        #expect(expired.primary == 72)
        #expect(expired.secondary == nil)
    }

    @Test func `single weekly window becomes one original icon meter`() {
        let values = CodexStatusIcon.values(windows: [self.window(used: 46)], now: self.now)
        #expect(values.primary == 54)
        #expect(values.secondary == nil)
    }

    @Test func `original fill rounding and plan labels are retained`() {
        #expect(UsageProgressBar.renderedFillPercent(0.3) == 0)
        #expect(UsageProgressBar.renderedFillPercent(99.6) == 100)
        #expect(CodexPlanFormatting.displayName("pro") == "Pro 20x")
        #expect(CodexPlanFormatting.displayName("pro_lite") == "Pro 5x")
    }
}
