// Upstream CodexBar (MIT), display helpers retained verbatim.
import CodexBarLiteCore
import Foundation

enum UsageFormatter {
    static func percentText(_ percent: Double, suffix: String) -> String {
        let clamped = min(100, max(0, percent))
        if clamped > 0, clamped < 1 {
            return L("<1%% %@", suffix)
        }
        return L("%.0f%% %@", clamped, suffix)
    }

    static func resetCountdownDescription(from date: Date, now: Date = .init()) -> String {
        guard let totalMinutes = self.resetCountdownMinutes(from: date, now: now) else {
            return L("Unknown")
        }
        if totalMinutes == 0 { return "now" }
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes / 60) % 24
        let minutes = totalMinutes % 60

        if days > 0 {
            if hours > 0 { return "in \(days)d \(hours)h" }
            if minutes > 0 { return "in \(days)d \(minutes)m" }
            return "in \(days)d"
        }
        if hours > 0 {
            if minutes > 0 { return "in \(hours)h \(minutes)m" }
            return "in \(hours)h"
        }
        return "in \(totalMinutes)m"
    }

    private static func resetCountdownMinutes(from date: Date, now: Date) -> Int? {
        let seconds = date.timeIntervalSince(now)
        guard let minutes = Int(exactly: ceil(seconds / 60)) else { return nil }
        return seconds < 1 ? 0 : max(1, minutes)
    }

    static func resetDescription(from date: Date, now: Date = .init()) -> String {
        // Human-friendly phrasing: today / tomorrow / date+time.
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) {
            return date.formatted(.dateTime.hour().minute().locale(Locale(identifier: "zh-Hans")))
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow)
        {
            let timeStr = date.formatted(.dateTime.hour().minute().locale(Locale(identifier: "zh-Hans")))
            return L("reset_tomorrow_format", timeStr)
        }
        return date.formatted(.dateTime.month(.abbreviated).day().hour().minute().locale(Locale(identifier: "zh-Hans")))
    }

    static func resetLine(
        for window: RateWindow,
        style: ResetTimeDisplayStyle,
        now: Date = .init()) -> String?
    {
        if let date = window.resetsAt, self.resetCountdownMinutes(from: date, now: now) != nil {
            if style == .countdown {
                let countdown = self.resetCountdownDescription(from: date, now: now)
                if countdown == "now" {
                    return L("Resets now")
                }
                if countdown.hasPrefix("in ") {
                    return L("Resets in %@", String(countdown.dropFirst(3)))
                }
                return L("Resets %@", countdown)
            }
            let text = self.resetDescription(from: date, now: now)
            return L("Resets %@", text)
        }

        if let desc = window.resetDescription {
            let trimmed = desc.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let lowercased = trimmed.lowercased()
            for prefix in ["resets in ", "reset in "] where lowercased.hasPrefix(prefix) {
                return L("Resets in %@", String(trimmed.dropFirst(prefix.count)))
            }
            for prefix in ["resets ", "reset "] where lowercased.hasPrefix(prefix) {
                return L("Resets %@", String(trimmed.dropFirst(prefix.count)))
            }
            return L("Resets %@", trimmed)
        }
        return nil
    }

    static func cleanPlanName(_ text: String) -> String {
        let stripped = TextParsing.stripANSICodes(text)
        let withoutCodes = stripped.replacingOccurrences(
            of: #"^\s*(?:\[\d{1,3}m\s*)+"#,
            with: "",
            options: [.regularExpression])
        let withoutBoilerplate = withoutCodes.replacingOccurrences(
            of: #"(?i)\b(claude|codex|account|plan)\b"#,
            with: "",
            options: [.regularExpression])
        var cleaned = withoutBoilerplate
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty {
            cleaned = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if cleaned.lowercased() == "oauth" {
            return "Ollama"
        }
        // Capitalize first letter only if lowercase, preserving acronyms like "AI"
        if let first = cleaned.first, first.isLowercase {
            return cleaned.prefix(1).uppercased() + cleaned.dropFirst()
        }
        return cleaned
    }

    static func updatedString(from date: Date, now: Date = .init()) -> String {
        let delta = now.timeIntervalSince(date)
        guard let elapsedSeconds = Int(exactly: delta.rounded(.towardZero)) else {
            return L("Updated absolute %@", L("Unknown"))
        }
        if elapsedSeconds > -60, elapsedSeconds < 60 {
            return L("Updated just now")
        }
        if let hours = Calendar.current.dateComponents([.hour], from: date, to: now).hour, hours < 24 {
            #if os(macOS)
            let rel = RelativeDateTimeFormatter()
            rel.locale = Locale(identifier: "zh-Hans")
            rel.unitsStyle = .abbreviated
            return L("Updated relative %@", rel.localizedString(for: date, relativeTo: now))
            #else
            let seconds = max(0, elapsedSeconds)
            if seconds < 3600 {
                let minutes = max(1, seconds / 60)
                return L("Updated %@m ago", String(minutes))
            }
            let wholeHours = max(1, seconds / 3600)
            return L("Updated %@h ago", String(wholeHours))
            #endif
        } else {
            return L(
                "Updated absolute %@",
                date.formatted(.dateTime.hour().minute().locale(Locale(identifier: "zh-Hans"))))
        }
    }
}
