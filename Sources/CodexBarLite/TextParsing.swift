// Upstream ANSI stripping helper (MIT).
import Foundation

public enum TextParsing {
    /// Removes ANSI escape sequences so regex parsing works on colored terminal output.
    public static func stripANSICodes(_ text: String) -> String {
        // CSI sequences: ESC [ ... ending in 0x40–0x7E
        let pattern = #"\u001B\[[0-?]*[ -/]*[@-~]"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }
}
