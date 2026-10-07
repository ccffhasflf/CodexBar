import AppKit
import CodexBarLiteCore

/// Preserve the original installed app's combined (undecorated) icon style.
/// Data still comes only from Codex; visual style does not require multiple providers.
enum CodexStatusIcon {
    static func values(windows: [QuotaWindow], now: Date) -> (primary: Double?, secondary: Double?) {
        // CodexProviderDescriptor.visibleWindows: weekly exhaustion caps the session,
        // and expired, exhausted lanes are hidden until the service reports a new window.
        let main = windows.filter { ["session", "weekly", "monthly"].contains($0.id) }
        let weekly = main.first { $0.id == "weekly" }
        let weeklyCapsSession = weekly
            .map { $0.remainingPercent <= 0 && ($0.resetsAt.map { $0 > now } ?? true) } ?? false
        let visible = main.compactMap { window -> Double? in
            let remaining = window.id == "session" && weeklyCapsSession ? 0 : window.remainingPercent
            guard remaining > 0 || window.resetsAt.map({ $0 > now }) != false else { return nil }
            return remaining
        }
        return (visible.first, visible.dropFirst().first)
    }

    static func make(windows: [QuotaWindow], stale: Bool, now: Date = Date()) -> NSImage {
        let values = self.values(windows: windows, now: now)
        return IconRenderer.makeIcon(primaryRemaining: values.primary, weeklyRemaining: values.secondary, stale: stale)
    }
}
