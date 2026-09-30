import Foundation

/// User preferences, stored in UserDefaults. The settings window binds to the
/// same keys, and the app re-applies them whenever defaults change.
public enum Settings {
    public enum Key {
        public static let expiryHours = "expiryHours"
        public static let trashDays = "voidDays" // stored under its original name
        public static let checkedItems = "checkedItems"
        public static let theme = "theme"
        public static let paper = "paper"
        public static let textSize = "textSize"
        public static let font = "font"
        public static let translucent = "translucent"
        public static let showInDock = "showInDock"
        public static let showInMenuBar = "showInMenuBar"
        /// Legacy on/off for "under the menu bar icon"; read once as a fallback.
        public static let dropdown = "dropdown"
        public static let windowPosition = "windowPosition"
        public static let animateWindow = "animateWindow"
        public static let keepOnTop = "keepOnTop"
        public static let hotkeyKeyCode = "hotkeyKeyCode"
        public static let hotkeyModifiers = "hotkeyModifiers"
        public static let hotkeyLabel = "hotkeyLabel"
        public static let reminderEnabled = "reminderEnabled"
        public static let reminderMinutes = "reminderMinutes"
        static let lastNoteID = "lastNoteID"
        /// Renamed first-line keywords, from before keywords were removed.
        static let legacyKeywords = ["keywordList", "keywordCode", "keywordPin"]
        static let keywordsRemoved = "keywordsRemoved"
    }

    public enum Default {
        public static let expiryHours = 72.0
        public static let trashDays = 7.0
        public static let textSize = 14.0
        /// kVK_ANSI_P and Carbon's optionKey: ⌥P.
        public static let hotkeyKeyCode = 35
        public static let hotkeyModifiers = 2048
        public static let hotkeyLabel = "⌥P"
        public static let reminderMinutes = 30.0
    }

    private static var defaults: UserDefaults { .standard }

    private static func double(_ key: String, _ fallback: Double) -> Double {
        defaults.object(forKey: key) as? Double ?? fallback
    }

    private static func bool(_ key: String, _ fallback: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? fallback
    }

    private static func string(_ key: String) -> String? {
        let value = defaults.string(forKey: key)?.trimmingCharacters(in: .whitespaces)
        return value?.isEmpty == false ? value : nil
    }

    // MARK: Notes

    /// How long an unpinned note lives after its last edit. Default 3 days.
    public static var noteTTL: TimeInterval { double(Key.expiryHours, Default.expiryHours) * 3600 }

    /// How long a note stays in Trash before it's gone for good. Default 7 days.
    public static var trashRetention: TimeInterval { double(Key.trashDays, Default.trashDays) * 86400 }

    /// What happens to a checklist item when it's checked. Default: stays put.
    public static var checkedBehavior: CheckedBehavior {
        CheckedBehavior(rawValue: string(Key.checkedItems) ?? "") ?? .keep
    }

    // MARK: Appearance

    public static var theme: String { string(Key.theme) ?? "tokyonight" }
    /// Font family; nil picks a Nerd Font if one is installed.
    public static var font: String? { string(Key.font) }
    public static var paper: String { string(Key.paper) ?? "blank" }
    public static var textSize: Double { double(Key.textSize, Default.textSize) }
    /// Sizes offered by the Settings slider and ⌘= / ⌘−.
    public static let textSizeRange = 10.0...24.0
    public static var translucent: Bool { bool(Key.translucent, false) }

    // MARK: Window

    public static var showInDock: Bool { bool(Key.showInDock, false) }
    public static var showInMenuBar: Bool { bool(Key.showInMenuBar, true) }
    /// Where the window appears each time it opens.
    public static var windowPosition: WindowPosition {
        if let raw = string(Key.windowPosition), let position = WindowPosition(rawValue: raw) { return position }
        return bool(Key.dropdown, false) ? .menuBar : .bottomRight
    }
    /// Quick fade/slide when the window opens and closes.
    public static var animateWindow: Bool { bool(Key.animateWindow, true) }
    /// On: floats over every app and Space until closed with the shortcut or
    /// esc. Off: hides as soon as Popnote loses focus (another app, ⌘Tab,
    /// switching Spaces).
    public static var keepOnTop: Bool {
        get { bool(Key.keepOnTop, false) }
        set { defaults.set(newValue, forKey: Key.keepOnTop) }
    }

    public static var hotkeyKeyCode: Int { defaults.object(forKey: Key.hotkeyKeyCode) as? Int ?? Default.hotkeyKeyCode }
    public static var hotkeyModifiers: Int { defaults.object(forKey: Key.hotkeyModifiers) as? Int ?? Default.hotkeyModifiers }
    public static var hotkeyLabel: String { string(Key.hotkeyLabel) ?? Default.hotkeyLabel }

    // MARK: Reminder

    /// Pops the panel up again on a timer after it's closed. Off by default.
    public static var reminderEnabled: Bool {
        get { bool(Key.reminderEnabled, false) }
        set { defaults.set(newValue, forKey: Key.reminderEnabled) }
    }
    /// How long after closing the panel it pops back up. Default 30 minutes.
    public static var reminderInterval: TimeInterval {
        let minutes = double(Key.reminderMinutes, Default.reminderMinutes)
        return (min(max(minutes, shortestReminder), reminderMinutesRange.upperBound) * 60).rounded()
    }
    /// The quickest preset, 5 seconds (stored in minutes like the rest).
    public static let shortestReminder = 5.0 / 60
    /// Custom intervals Settings accepts: 1 minute to 24 hours.
    public static let reminderMinutesRange = 1.0...1440.0

    // MARK: State

    public static var lastNoteID: Int64? {
        get { (defaults.object(forKey: Key.lastNoteID) as? NSNumber)?.int64Value }
        set { defaults.set(newValue.map { NSNumber(value: $0) }, forKey: Key.lastNoteID) }
    }

    // MARK: Upgrades

    /// A note's first line used to be a keyword: "list", "code" or "pin" (or
    /// words renamed in Settings), and "pin" pinned the note. Until
    /// `removeKeywords()` runs, these are those words.
    public static var legacyKeywords: (pin: String, all: Set<String>)? {
        guard !bool(Key.keywordsRemoved, false) else { return nil }
        let pin = string("keywordPin")?.lowercased() ?? "pin"
        let list = string("keywordList")?.lowercased() ?? "list"
        let code = string("keywordCode")?.lowercased() ?? "code"
        return (pin, [list, code, pin])
    }

    public static func removeKeywords() {
        Key.legacyKeywords.forEach(defaults.removeObject(forKey:))
        defaults.set(true, forKey: Key.keywordsRemoved)
    }
}

public enum WindowPosition: String, CaseIterable {
    /// Bottom-right corner of the screen the mouse is on.
    case bottomRight
    /// Wherever you last moved it.
    case remember
    /// Hanging under the menu bar icon.
    case menuBar
}
