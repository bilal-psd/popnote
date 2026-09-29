import Foundation

/// What happens to an item when it's checked off.
public enum CheckedBehavior: String, CaseIterable {
    case keep
    /// Moves to the end of its list (the run of consecutive list lines).
    case moveToBottom
    case delete
}

public enum Checklist {
    /// Toggles the checkbox on line `index` and applies `behavior` if it was
    /// just checked. Unchecking never moves anything. Returns the new lines and
    /// where the toggled line ended up (nil if deleted).
    public static func toggle(lines: [String], at index: Int, behavior: CheckedBehavior) -> (lines: [String], index: Int?) {
        var lines = lines
        let parsed = Markers.parse(lines[index])
        guard case .checkbox(let wasChecked) = parsed.kind else { return (lines, index) }

        let line = parsed.indent + Markers.marker(for: .checkbox(checked: !wasChecked)) + parsed.content
        lines[index] = line
        if wasChecked { return (lines, index) }

        switch behavior {
        case .keep:
            return (lines, index)
        case .delete:
            lines.remove(at: index)
            return (lines, nil)
        case .moveToBottom:
            var end = index
            while end + 1 < lines.count, Markers.parse(lines[end + 1]).kind != .plain { end += 1 }
            lines.remove(at: index)
            lines.insert(line, at: end)
            return (lines, end)
        }
    }
}
