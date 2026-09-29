import Foundation

/// A note's text as shown outside the editor. The keyword line ("list",
/// "code", "pin") is Popnote-only, so it's left out.
public enum NoteText {
    /// The note's text without its keyword line. This is what ⌘C copies.
    public static func content(of note: Note, keywords: Keywords = .current) -> String {
        guard let keyword = note.keyword, keywords.firstLine.contains(keyword) else { return note.body }
        let rest = note.body.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).dropFirst().first
        return String(rest ?? "")
    }

    /// First non-empty line without list markers, cut to 60 characters.
    public static func title(of note: Note, keywords: Keywords = .current, fallback: String = "empty note") -> String {
        let line = content(of: note, keywords: keywords)
            .split(separator: "\n")
            .map { Markers.parse(String($0)).content.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty }) ?? ""
        let title = line.count > 60 ? String(line.prefix(60)).trimmingCharacters(in: .whitespaces) + "…" : line
        return title.isEmpty ? fallback : title
    }
}
