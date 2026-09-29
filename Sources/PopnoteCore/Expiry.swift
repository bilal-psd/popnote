import Foundation

public enum Expiry {
    /// When an unpinned note moves to The Void. Nil for pinned notes.
    public static func expiresAt(_ note: Note, ttl: TimeInterval) -> Date? {
        note.isPinned ? nil : note.updatedAt.addingTimeInterval(ttl)
    }

    public static func isExpired(_ note: Note, now: Date, ttl: TimeInterval) -> Bool {
        guard let date = expiresAt(note, ttl: ttl) else { return false }
        return date <= now
    }

    /// "deletes in 2d 5h", "deletes in 5h", "deletes in 12m", "deletes in <1m".
    public static func label(for note: Note, now: Date, ttl: TimeInterval) -> String? {
        remaining(for: note, now: now, ttl: ttl).map { "deletes in \($0)" }
    }

    /// Time left: "2d 5h", "5h", "12m", "<1m". Nil for pinned notes.
    public static func remaining(for note: Note, now: Date, ttl: TimeInterval) -> String? {
        guard let date = expiresAt(note, ttl: ttl) else { return nil }
        let remaining = max(0, date.timeIntervalSince(now))
        let minutes = Int(remaining / 60)
        let hours = minutes / 60
        let days = hours / 24
        let text: String
        if days > 0 {
            text = hours % 24 == 0 ? "\(days)d" : "\(days)d \(hours % 24)h"
        } else if hours > 0 {
            text = "\(hours)h"
        } else if minutes > 0 {
            text = "\(minutes)m"
        } else {
            text = "<1m"
        }
        return text
    }
}
