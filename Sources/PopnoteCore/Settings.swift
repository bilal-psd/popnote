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
        public static let dropdown = "dropdown"
        public static let keepOnTop = "keepOnTop"
        public static let hotkeyKeyCode = "hotkeyKeyCode"
        public static let hotkeyModifiers = "hotkeyModifiers"
        public static let hotkeyLabel = "hotkeyLabel"
        public static let keywordList = "keywordList"
        public static let keywordCode = "keywordCode"
        public static let keywordPin = "keywordPin"
        public static let keywordCheck = "keywordCheck"
        public static let obsidianVault = "obsidianVault"
        static let lastNoteID = "lastNoteID"
    }

    public enum Default {
        public static let expiryHours = 72.0
        public static let trashDays = 7.0
        public static let textSize = 14.0
        /// kVK_ANSI_A and Carbon's optionKey: ⌥A.
        public static let hotkeyKeyCode = 0
        public static let hotkeyModifiers = 2048
        public static let hotkeyLabel = "⌥A"
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

    public static var keywords: Keywords {
        var k = Keywords.standard
        if let v = string(Key.keywordList) { k.list = v.lowercased() }
        if let v = string(Key.keywordCode) { k.code = v.lowercased() }
        if let v = string(Key.keywordPin) { k.pin = v.lowercased() }
        if let v = string(Key.keywordCheck) { k.check = v.lowercased() }
        return k
    }

    // MARK: Appearance

    public static var theme: String { string(Key.theme) ?? "tokyonight" }
    /// Font family; nil picks a Nerd Font if one is installed.
    public static var font: String? { string(Key.font) }
    public static var paper: String { string(Key.paper) ?? "blank" }
    public static var textSize: Double { double(Key.textSize, Default.textSize) }
    public static var translucent: Bool { bool(Key.translucent, false) }

    // MARK: Window

    public static var showInDock: Bool { bool(Key.showInDock, false) }
    public static var showInMenuBar: Bool { bool(Key.showInMenuBar, true) }
    /// Panel drops down under the menu bar icon and hides when you click away.
    public static var dropdown: Bool { bool(Key.dropdown, false) }
    public static var keepOnTop: Bool {
        get { bool(Key.keepOnTop, false) }
        set { defaults.set(newValue, forKey: Key.keepOnTop) }
    }

    public static var hotkeyKeyCode: Int { defaults.object(forKey: Key.hotkeyKeyCode) as? Int ?? Default.hotkeyKeyCode }
    public static var hotkeyModifiers: Int { defaults.object(forKey: Key.hotkeyModifiers) as? Int ?? Default.hotkeyModifiers }
    public static var hotkeyLabel: String { string(Key.hotkeyLabel) ?? Default.hotkeyLabel }

    // MARK: Export

    public static var obsidianVault: String? { string(Key.obsidianVault) }

    // MARK: State

    public static var lastNoteID: Int64? {
        get { (defaults.object(forKey: Key.lastNoteID) as? NSNumber)?.int64Value }
        set { defaults.set(newValue.map { NSNumber(value: $0) }, forKey: Key.lastNoteID) }
    }
}

/// The trigger words, which you can rename in Settings.
public struct Keywords: Equatable {
    public var list = "list"
    public var code = "code"
    public var pin = "pin"
    /// Typed at the end of an unchecked item to check it off.
    public var check = "/x"

    public static let standard = Keywords()
    public static var current: Keywords { Settings.keywords }

    /// First-line words that change how a note behaves.
    public var firstLine: Set<String> { [list, code, pin] }
}
