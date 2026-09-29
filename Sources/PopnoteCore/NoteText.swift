import Foundation

/// A note's text as shown outside the editor.
public enum NoteText {
    /// First non-empty line without list markers, cut to 60 characters.
    public static func title(of note: Note, fallback: String = "empty note") -> String {
        let line = note.body
            .split(separator: "\n")
            .map { Markers.parse(String($0)).content.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty }) ?? ""
        let title = line.count > 60 ? String(line.prefix(60)).trimmingCharacters(in: .whitespaces) + "…" : line
        return title.isEmpty ? fallback : title
    }
}
