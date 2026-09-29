import Foundation

public enum Expiry {
    /// When an unpinned note moves to Trash. Nil for pinned notes.
    public static func expiresAt(_ note: Note, ttl: TimeInterval) -> Date? {
        note.isPinned ? nil : note.updatedAt.addingTimeInterval(ttl)
    }

    public static func isExpired(_ note: Note, now: Date, ttl: TimeInterval) -> Bool {
        guard let date = expiresAt(note, ttl: ttl) else { return false }
        return date <= now
    }
}
