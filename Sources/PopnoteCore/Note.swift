import Foundation

public struct Note: Identifiable, Equatable {
    public let id: Int64
    public var body: String
    public var createdAt: Date
    public var updatedAt: Date
    /// Pinned with ⌘P or the pin button. See `isPinned` for the effective state.
    public var pinned: Bool
    /// Set when the note is in The Void.
    public var deletedAt: Date?

    public init(id: Int64, body: String, createdAt: Date, updatedAt: Date, pinned: Bool = false, deletedAt: Date? = nil) {
        self.id = id
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.pinned = pinned
        self.deletedAt = deletedAt
    }

    /// The first line, trimmed and lowercased, e.g. "list", "code", "pin".
    public var keyword: String? {
        let first = body.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        let word = first.trimmingCharacters(in: .whitespaces).lowercased()
        return word.isEmpty ? nil : word
    }

    public var isPinnedByKeyword: Bool { keyword == "pin" }

    /// Pinned either by flag or by a "pin" first line. Pinned notes never expire.
    public var isPinned: Bool { pinned || isPinnedByKeyword }

    public var isBlank: Bool { body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// First non-empty line, for lists like The Void.
    public var preview: String {
        body.split(separator: "\n").first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
            .map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
    }
}
