import Foundation

/// What the notes drawer shows: pinned notes first, then the rest, each
/// group ordered by most recently edited.
public enum Browse {
    public struct Sections: Equatable {
        public var pinned: [Note]
        public var recent: [Note]
    }

    /// `filter` matches anywhere in a note's text, ignoring case.
    public static func sections(_ notes: [Note], filter: String = "") -> Sections {
        let query = filter.trimmingCharacters(in: .whitespaces)
        let matching = query.isEmpty ? notes : notes.filter { $0.body.localizedCaseInsensitiveContains(query) }
        let byRecency = matching.sorted { $0.updatedAt != $1.updatedAt ? $0.updatedAt > $1.updatedAt : $0.id > $1.id }
        return Sections(pinned: byRecency.filter(\.pinned), recent: byRecency.filter { !$0.pinned })
    }

    /// Time since the last edit: "now", "5m", "2h", "3d".
    public static func age(of note: Note, now: Date = Date()) -> String {
        let minutes = Int(max(0, now.timeIntervalSince(note.updatedAt)) / 60)
        if minutes < 1 { return "now" }
        if minutes < 60 { return "\(minutes)m" }
        if minutes < 60 * 24 { return "\(minutes / 60)h" }
        return "\(minutes / 60 / 24)d"
    }
}
