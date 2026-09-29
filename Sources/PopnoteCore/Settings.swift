import Foundation

/// User preferences. The settings window comes in pass 3; until then
/// these can be changed with `defaults write com.popnote.Popnote <key> <value>`.
public enum Settings {
    private static let defaults = UserDefaults.standard

    /// How long an unpinned note lives after its last edit. Default 3 days.
    public static var noteTTL: TimeInterval {
        let hours = defaults.object(forKey: "expiryHours") as? Double ?? 72
        return hours * 3600
    }

    /// How long a note stays in The Void before it's gone for good. Default 7 days.
    public static var voidRetention: TimeInterval {
        let days = defaults.object(forKey: "voidDays") as? Double ?? 7
        return days * 86400
    }

    /// What happens to a checklist item when it's checked. Default: stays put.
    public static var checkedBehavior: CheckedBehavior {
        CheckedBehavior(rawValue: defaults.string(forKey: "checkedItems") ?? "") ?? .keep
    }

    public static var lastNoteID: Int64? {
        get { (defaults.object(forKey: "lastNoteID") as? NSNumber)?.int64Value }
        set { defaults.set(newValue.map { NSNumber(value: $0) }, forKey: "lastNoteID") }
    }
}
