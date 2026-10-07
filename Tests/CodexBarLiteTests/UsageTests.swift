import Foundation
import Testing
@testable import CodexBarLiteCore

struct UsageTests {
    @Test func `main windows retain percentages and reset timestamps`() throws {
        let value = try UsageSnapshot.decode(Fixture.usage, email: "fixture@example.com")
        #expect(value.windows.map(\.id) == ["session", "weekly"])
        #expect(value.menuWindow?.remainingPercent == 75)
        #expect(value.windows[0].resetsAt == Date(timeIntervalSince1970: 2_000_000_000))
        #expect(value.plan == "plus")
    }

    @Test func `a weekly-only plan never fabricates a five hour quota`() throws {
        let data = Data("""
        {"rate_limit":{"primary_window":{"used_percent":20,"reset_at":0,"limit_window_seconds":604800}}}
        """.utf8)
        let value = try UsageSnapshot.decode(data, email: nil)
        #expect(value.windows.count == 1)
        #expect(value.menuWindow?.id == "weekly")
        #expect(value.menuWindow?.resetsAt == nil)
    }

    @Test func `exhausted weekly limit binds the menu percentage`() throws {
        let data = try Data(#require(String(data: Fixture.usage, encoding: .utf8)?
                .replacingOccurrences(of: "\"used_percent\":60", with: "\"used_percent\":100").utf8))
        #expect(try UsageSnapshot.decode(data, email: nil).menuWindow?.remainingPercent == 0)
    }

    @Test func `malformed optional limits do not discard valid quota windows`() throws {
        let data = Data("""
        {"plan_type":"future-plan","rate_limit":{
          "primary_window":{"used_percent":30,"reset_at":0,"limit_window_seconds":18000},
          "secondary_window":"bad"},"additional_rate_limits":[null,42,
          {"limit_name":"Extra","rate_limit":{"primary_window":{
            "used_percent":50,"reset_at":0,"limit_window_seconds":18000}}}]}
        """.utf8)
        let value = try UsageSnapshot.decode(data, email: nil)
        #expect(value.windows.count == 2)
        #expect(value.plan == "future-plan")
    }

    @Test func `monthly workspace quota accepts numeric strings and precedence`() throws {
        let data = Data("""
        {"individual_limit":{"limit":"100","used":"40","reset_at":"2000000000"},
         "spend_control":{"individual_limit":{"remaining_percent":"10"}}}
        """.utf8)
        let value = try UsageSnapshot.decode(data, email: nil)
        #expect(value.windows.first?.id == "monthly")
        #expect(value.windows.first?.remainingPercent == 60)
    }

    @Test func `missing quota is an error rather than a fabricated full allowance`() {
        #expect(throws: (any Error).self) { try UsageSnapshot.decode(Data("{}".utf8), email: nil) }
    }

    @Test func `reset countdown does not claim quota has refilled`() {
        let now = Date(timeIntervalSince1970: 1000)
        let window = QuotaWindow(
            id: "session",
            title: "Quota",
            usedPercent: 80,
            resetsAt: now.addingTimeInterval(-1),
            durationSeconds: 18000)
        #expect(window.resetLabel(now: now).contains("等待刷新"))
        #expect(window.remainingPercent == 20)
    }

    @Test func `negative and overflowing percentages are clamped`() throws {
        let data = try Data(#require(String(data: Fixture.usage, encoding: .utf8)?
                .replacingOccurrences(of: "\"used_percent\":25", with: "\"used_percent\":-10")
                .replacingOccurrences(of: "\"used_percent\":60", with: "\"used_percent\":120").utf8))
        let value = try UsageSnapshot.decode(data, email: nil)
        #expect(value.windows.map(\.remainingPercent) == [100, 0])
    }
}
