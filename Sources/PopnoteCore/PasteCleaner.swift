import Foundation

/// Cleans pasted text: trims each line and strips bullets and numbering, so
/// text arrives plain wherever it came from. Markdown checkboxes are kept.
public enum PasteCleaner {
    private static let bulletCharacters: Set<Character> = ["•", "◦", "▪", "▫", "‣", "⁃", "●", "○", "■", "□", "–", "—", "·", "-", "*", "+"]

    /// - Parameters:
    ///   - linePrefix: marker to put in front of pasted lines (when pasting into a list).
    ///   - prefixFirstLine: whether the first line gets `linePrefix` too. It doesn't
    ///     when it lands on a line that already has a marker.
    ///   - dropEmptyLines: used in `list` notes, where blank lines make no sense.
    public static func clean(_ raw: String, linePrefix: String? = nil, prefixFirstLine: Bool = false,
                             dropEmptyLines: Bool = false) -> String {
        let lines = raw.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        var out: [String] = []
        for rawLine in lines {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            let isCheckbox: Bool
            if case .checkbox = Markers.parse(line).kind {
                isCheckbox = true
            } else {
                isCheckbox = false
                line = stripListPrefix(line)
            }
            if line.isEmpty && dropEmptyLines { continue }
            if let linePrefix, !line.isEmpty, !isCheckbox, !out.isEmpty || prefixFirstLine {
                line = linePrefix + line
            }
            out.append(line)
        }
        return out.joined(separator: "\n")
    }

    /// "• item", "- item", "3. item", "3) item" → "item".
    static func stripListPrefix(_ line: String) -> String {
        if let first = line.first, bulletCharacters.contains(first),
           line.dropFirst().first?.isWhitespace == true {
            return line.dropFirst().trimmingCharacters(in: .whitespaces)
        }
        let digits = line.prefix(while: { $0.isASCII && $0.isNumber })
        let afterDigits = line.dropFirst(digits.count)
        if (1...3).contains(digits.count), let punct = afterDigits.first, punct == "." || punct == ")",
           afterDigits.dropFirst().first?.isWhitespace == true {
            return afterDigits.dropFirst().trimmingCharacters(in: .whitespaces)
        }
        return line
    }
}
