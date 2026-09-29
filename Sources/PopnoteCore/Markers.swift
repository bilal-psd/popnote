import Foundation

/// What a line is, based on the marker at its start (after indentation).
public enum LineKind: Equatable {
    case plain
    case checkbox(checked: Bool)   // "- [ ] " / "- [x] "
    case bullet                    // "- " or "* "
    case numbered(Int)             // "1. "
}

public struct ParsedLine: Equatable {
    /// Leading tabs/spaces.
    public var indent: String
    public var kind: LineKind
    /// Length of the marker after the indent; 0 for plain lines. Markers are ASCII,
    /// so this is also the UTF-16 length.
    public var markerLength: Int
    /// Everything after the marker.
    public var content: String
}

public enum NewlineAction: Equatable {
    /// Ordinary newline.
    case plain
    /// Newline followed by this prefix (indent + marker).
    case continueWith(String)
    /// The item is empty: remove its marker instead of adding a new item.
    case endList
    /// The caret is before the item's text: add this empty item (indent +
    /// marker) above it, and leave the current item as it is.
    case insertAbove(String)
}

/// Line-level rules for checklists, bullets and numbered lists. Markers live
/// in the text as Markdown, so copied notes read cleanly anywhere.
public enum Markers {
    public static func parse(_ line: String) -> ParsedLine {
        let indent = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
        let rest = line.dropFirst(indent.count)
        func found(_ kind: LineKind, _ length: Int) -> ParsedLine {
            ParsedLine(indent: indent, kind: kind, markerLength: length, content: String(rest.dropFirst(length)))
        }
        if rest.hasPrefix("- [ ] ") { return found(.checkbox(checked: false), 6) }
        if rest.hasPrefix("- [x] ") || rest.hasPrefix("- [X] ") { return found(.checkbox(checked: true), 6) }
        if rest.hasPrefix("- ") || rest.hasPrefix("* ") { return found(.bullet, 2) }
        let digits = rest.prefix(while: { $0.isASCII && $0.isNumber })
        if (1...3).contains(digits.count), rest.dropFirst(digits.count).hasPrefix(". "), let n = Int(digits) {
            return found(.numbered(n), digits.count + 2)
        }
        return ParsedLine(indent: indent, kind: .plain, markerLength: 0, content: String(rest))
    }

    public static func marker(for kind: LineKind) -> String {
        switch kind {
        case .plain: return ""
        case .checkbox(let checked): return checked ? "- [x] " : "- [ ] "
        case .bullet: return "- "
        case .numbered(let n): return "\(n). "
        }
    }

    /// Indent + marker for the item that follows `line`, or nil for plain lines.
    /// New checkboxes start unchecked; numbers count up.
    public static func continuationPrefix(for line: String) -> String? {
        let parsed = parse(line)
        let next: LineKind
        switch parsed.kind {
        case .plain: return nil
        case .checkbox: next = .checkbox(checked: false)
        case .bullet: next = .bullet
        case .numbered(let n): next = .numbered(n + 1)
        }
        return parsed.indent + marker(for: next)
    }

    /// What Enter should do on `line` with the caret `caret` UTF-16 units into
    /// it (nil: at the end).
    public static func newlineAction(for line: String, caret: Int? = nil) -> NewlineAction {
        let parsed = parse(line)
        let isEmpty = parsed.content.trimmingCharacters(in: .whitespaces).isEmpty
        // Indent and markers are ASCII, so these counts are UTF-16 lengths too.
        let contentStart = parsed.indent.utf16.count + parsed.markerLength
        let beforeContent = caret.map { $0 <= contentStart } ?? false
        guard let prefix = continuationPrefix(for: line) else { return .plain }
        if isEmpty { return .endList }
        if beforeContent {
            let kind: LineKind = parsed.kind == .checkbox(checked: true) ? .checkbox(checked: false) : parsed.kind
            return .insertAbove(parsed.indent + marker(for: kind))
        }
        return .continueWith(prefix)
    }

    public static func indented(_ line: String) -> String {
        "\t" + line
    }

    public static func outdented(_ line: String) -> String {
        if line.hasPrefix("\t") { return String(line.dropFirst()) }
        let spaces = line.prefix(while: { $0 == " " }).count
        return String(line.dropFirst(min(spaces, 4)))
    }

    /// Typing "[] " or "[ ] " at the start of a line makes a checkbox.
    /// `prefix` is the line's text up to the caret.
    public static func expandShortcut(_ prefix: String) -> String? {
        let indent = String(prefix.prefix(while: { $0 == " " || $0 == "\t" }))
        let rest = prefix.dropFirst(indent.count)
        guard rest == "[] " || rest == "[ ] " else { return nil }
        return indent + marker(for: .checkbox(checked: false))
    }
}
