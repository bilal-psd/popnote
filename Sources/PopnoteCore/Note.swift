import Foundation

public struct Note: Identifiable, Equatable {
    public let id: Int64
    public var body: String
    public var createdAt: Date
    public var updatedAt: Date
    /// Pinned with ⌘P or the pin button. Pinned notes never expire.
    public var pinned: Bool
    /// Set when the note is in Trash.
    public var deletedAt: Date?

    public init(id: Int64, body: String, createdAt: Date, updatedAt: Date, pinned: Bool = false, deletedAt: Date? = nil) {
        self.id = id
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.pinned = pinned
        self.deletedAt = deletedAt
    }

    public var isBlank: Bool { body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// First non-empty line, for lists like Trash.
    public var preview: String {
        body.split(separator: "\n").first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
            .map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
    }
}
