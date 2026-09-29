import AppKit
import Carbon
import PopnoteCore
import ServiceManagement
import SwiftUI

private typealias Key = PopnoteCore.Settings.Key

/// Explanation under a section, wrapping left-aligned.
private struct FooterText: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption).foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: General

private struct GeneralSettings: View {
    @AppStorage(Key.expiryHours) private var expiryHours = PopnoteCore.Settings.Default.expiryHours
    @AppStorage(Key.trashDays) private var trashDays = PopnoteCore.Settings.Default.trashDays
    @AppStorage(Key.checkedItems) private var checkedItems = CheckedBehavior.keep.rawValue
    @AppStorage(Key.reminderEnabled) private var reminderEnabled = false
    @AppStorage(Key.reminderMinutes) private var reminderMinutes = PopnoteCore.Settings.Default.reminderMinutes
    @State private var customReminder = !reminderPresets.contains(
        UserDefaults.standard.object(forKey: Key.reminderMinutes) as? Double ?? PopnoteCore.Settings.Default.reminderMinutes)
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Notes") {
                Picker("Unpinned notes delete after", selection: $expiryHours) {
                    Text("1 day").tag(24.0)
                    Text("3 days").tag(72.0)
                    Text("1 week").tag(168.0)
                    Text("2 weeks").tag(336.0)
                }
                Picker("Trash keeps notes for", selection: $trashDays) {
                    Text("1 day").tag(1.0)
                    Text("7 days").tag(7.0)
                    Text("30 days").tag(30.0)
                }
                Picker("Checked items", selection: $checkedItems) {
                    Text("Stay in place").tag(CheckedBehavior.keep.rawValue)
                    Text("Move to the bottom").tag(CheckedBehavior.moveToBottom.rawValue)
                    Text("Delete themselves").tag(CheckedBehavior.delete.rawValue)
                }
            }
            Section {
                Toggle(isOn: $reminderEnabled) {
                    Text("Pop up the note on a timer")
                    Text("Opens Popnote again this long after you close it. ⌘R toggles this.")
                }
                Picker("Every", selection: reminderChoice) {
                    ForEach(Self.reminderPresets, id: \.self) { Text(Self.duration($0)).tag($0) }
                    Divider()
                    Text("Custom…").tag(Self.custom)
                }
                .disabled(!reminderEnabled)
                if customReminder {
                    LabeledContent("Minutes") {
                        HStack {
                            TextField("Minutes", value: customMinutes, format: .number)
                                .labelsHidden().multilineTextAlignment(.trailing).frame(width: 60)
                            Stepper("Minutes", value: customMinutes,
                                    in: PopnoteCore.Settings.reminderMinutesRange).labelsHidden()
                        }
                    }
                    .disabled(!reminderEnabled)
                }
            }
            Section {
                HotkeyRecorder()
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            } footer: {
                FooterText("To change other shortcuts, add them for Popnote in System Settings › Keyboard › Keyboard Shortcuts › App Shortcuts, using the menu item's name.")
            }
        }
        .formStyle(.grouped)
    }

    private static let reminderPresets = [PopnoteCore.Settings.shortestReminder, 15.0, 30.0, 60.0, 120.0]
    /// The picker's tag for "Custom…"; never a stored interval.
    private static let custom = -1.0

    /// A preset, or "Custom…" once picked or when the stored interval isn't a preset.
    private var reminderChoice: Binding<Double> {
        Binding {
            customReminder ? Self.custom : reminderMinutes
        } set: { choice in
            if choice != Self.custom {
                customReminder = false
                reminderMinutes = choice
            } else if !customReminder {
                // Custom starts from the default, not whichever preset was picked last.
                customReminder = true
                reminderMinutes = PopnoteCore.Settings.Default.reminderMinutes
            }
        }
    }

    /// Whole minutes, kept within the range the timer accepts.
    private var customMinutes: Binding<Double> {
        Binding {
            reminderMinutes
        } set: { minutes in
            let range = PopnoteCore.Settings.reminderMinutesRange
            reminderMinutes = min(max(minutes.rounded(), range.lowerBound), range.upperBound)
        }
    }

    private static func duration(_ minutes: Double) -> String {
        minutes < 1 ? "\(Int((minutes * 60).rounded())) seconds"
            : minutes < 60 ? "\(Int(minutes)) minutes" : minutes == 60 ? "1 hour" : "\(Int(minutes / 60)) hours"
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn't change this: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

// MARK: Appearance

private struct AppearanceSettings: View {
    @AppStorage(Key.theme) private var theme = Theme.all[0].id
    @AppStorage(Key.font) private var font = ""
    @AppStorage(Key.paper) private var paper = Paper.blank.rawValue
    @AppStorage(Key.textSize) private var textSize = PopnoteCore.Settings.Default.textSize
    @AppStorage(Key.translucent) private var translucent = false

    var body: some View {
        Form {
            Section {
                Picker("Theme", selection: $theme) {
                    ForEach(Theme.all, id: \.id) { Text($0.name).tag($0.id) }
                }
                Picker("Font", selection: $font) {
                    Text("Auto").tag("")
                    Divider()
                    ForEach(Fonts.installedMonospaced, id: \.self) { Text($0).tag($0) }
                }
                LabeledContent("Text size") {
                    HStack {
                        Slider(value: $textSize, in: PopnoteCore.Settings.textSizeRange, step: 1)
                        Text("\(Int(textSize)) pt").monospacedDigit().frame(width: 40, alignment: .trailing)
                    }
                    .frame(width: 220)
                }
            } footer: {
                if !Fonts.hasNerdGlyphs {
                    FooterText("Auto picks a Nerd Font if one is installed, for icons and powerline separators. Try `brew install --cask font-jetbrains-mono-nerd-font`.")
                }
            }
            Section {
                Picker("Paper", selection: $paper) {
                    ForEach(Paper.allCases, id: \.rawValue) { Text($0.name).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                Toggle("Translucent window", isOn: $translucent)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Window

private struct WindowSettings: View {
    @AppStorage(Key.showInMenuBar) private var showInMenuBar = true
    @AppStorage(Key.showInDock) private var showInDock = false
    @AppStorage(Key.windowPosition) private var position = PopnoteCore.Settings.windowPosition.rawValue
    @AppStorage(Key.animateWindow) private var animate = true
    @AppStorage(Key.hideOnClickOutside) private var hideOnClickOutside = true
    @AppStorage(Key.keepOnTop) private var keepOnTop = false
    @AppStorage(Key.hotkeyLabel) private var hotkeyLabel = PopnoteCore.Settings.Default.hotkeyLabel

    var body: some View {
        Form {
            Section {
                Toggle("Show in menu bar", isOn: $showInMenuBar)
                Toggle("Show in Dock", isOn: $showInDock)
            } footer: {
                if !showInMenuBar && !showInDock {
                    FooterText("Popnote will only open with \(hotkeyLabel).")
                }
            }
            Section {
                Picker("Open at", selection: $position) {
                    Text("Bottom right of the screen").tag(WindowPosition.bottomRight.rawValue)
                    Text("Where I left it").tag(WindowPosition.remember.rawValue)
                    Text("Under the menu bar icon").tag(WindowPosition.menuBar.rawValue)
                }
                Toggle(isOn: $animate) {
                    Text("Animate opening and closing")
                    Text("A quick fade and slide. Only fades when Reduce Motion is on.")
                }
            }
            Section {
                Toggle("Hide when clicking outside", isOn: $hideOnClickOutside)
                Toggle(isOn: $keepOnTop) {
                    Text("Keep on top of other windows")
                    Text("Also stops clicks outside from hiding it. ⌘T toggles this.")
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Hotkey recorder

/// Click, then press the new shortcut. It needs ⌘, ⌥ or ⌃; Esc cancels.
private struct HotkeyRecorder: View {
    @AppStorage(Key.hotkeyKeyCode) private var keyCode = PopnoteCore.Settings.Default.hotkeyKeyCode
    @AppStorage(Key.hotkeyModifiers) private var modifiers = PopnoteCore.Settings.Default.hotkeyModifiers
    @AppStorage(Key.hotkeyLabel) private var label = PopnoteCore.Settings.Default.hotkeyLabel
    @State private var monitor: Any?
    @State private var problem: String?

    var body: some View {
        LabeledContent {
            Button(monitor == nil ? label : "Type shortcut…") {
                monitor == nil ? start() : stop()
            }
        } label: {
            Text("Open Popnote from anywhere")
            // macOS keeps its own shortcuts (e.g. ⌘Space); they never reach Popnote.
            if let problem {
                Text(problem).foregroundStyle(.red)
            } else {
                Text(monitor == nil ? "Click the shortcut to change it." : "Press the new keys, or Esc to cancel. macOS's own shortcuts won't work.")
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        problem = nil
        // Only keys typed in this window count. Anything else (the window
        // closed, or the note panel came forward) ends recording.
        let window = NSApp.keyWindow
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { (event: NSEvent) -> NSEvent? in
            guard let window, event.window === window, window.isVisible else {
                stop()
                return event
            }
            if event.keyCode == UInt16(kVK_Escape) {
                stop()
                return nil
            }
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !flags.intersection([.command, .option, .control]).isEmpty else {
                NSSound.beep()
                return nil
            }
            let newKeyCode = Int(event.keyCode), newModifiers = carbonModifiers(flags)
            let newLabel = symbols(flags) + keyName(event)
            stop()
            // A global hotkey takes the keys from every app, so not ⌘C, ⌘Q and the like.
            if let taken = menuItem(for: event, flags: flags) {
                problem = "\(newLabel) is already Popnote's “\(taken.title)” shortcut."
                NSSound.beep()
                return nil
            }
            // Only fails when another app claimed the keys exclusively.
            let isCurrent = newKeyCode == keyCode && newModifiers == modifiers
            guard isCurrent || HotKey(keyCode: newKeyCode, modifiers: newModifiers, action: {}) != nil else {
                problem = "\(newLabel) can't be used: another app has it."
                NSSound.beep()
                return nil
            }
            keyCode = newKeyCode
            modifiers = newModifiers
            label = newLabel
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// The main-menu item (⌘C Copy, ⌘Q Quit…) that already uses these keys.
    private func menuItem(for event: NSEvent, flags: NSEvent.ModifierFlags) -> NSMenuItem? {
        let key = (event.charactersIgnoringModifiers ?? "").lowercased()
        func search(_ menu: NSMenu) -> NSMenuItem? {
            for item in menu.items {
                if let submenu = item.submenu, let found = search(submenu) { return found }
                guard !item.keyEquivalent.isEmpty else { continue }
                var mask = item.keyEquivalentModifierMask.intersection([.command, .option, .control, .shift])
                // An uppercase key equivalent ("Z" for Redo) implies ⇧.
                if item.keyEquivalent != item.keyEquivalent.lowercased() { mask.insert(.shift) }
                if item.keyEquivalent.lowercased() == key && mask == flags { return item }
            }
            return nil
        }
        return NSApp.mainMenu.flatMap(search)
    }

    private func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> Int {
        var result = 0
        if flags.contains(.command) { result |= cmdKey }
        if flags.contains(.option) { result |= optionKey }
        if flags.contains(.control) { result |= controlKey }
        if flags.contains(.shift) { result |= shiftKey }
        return result
    }

    private func symbols(_ flags: NSEvent.ModifierFlags) -> String {
        (flags.contains(.control) ? "⌃" : "") + (flags.contains(.option) ? "⌥" : "")
            + (flags.contains(.shift) ? "⇧" : "") + (flags.contains(.command) ? "⌘" : "")
    }

    private func keyName(_ event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        default: return (event.charactersIgnoringModifiers ?? "?").uppercased()
        }
    }
}

/// Remembers the last pane shown, so Settings reopens on it.
private final class SettingsTabs: NSTabViewController {
    static let paneKey = "settingsPane"

    override func tabView(_ tabView: NSTabView, didSelect item: NSTabViewItem?) {
        super.tabView(tabView, didSelect: item)
        UserDefaults.standard.set(selectedTabViewItemIndex, forKey: Self.paneKey)
    }
}

/// Toolbar tabs, like the system's own settings windows. The window
/// resizes to fit each tab, opens centred the first time and where it was
/// left after that.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private static let positionKey = "settingsTopLeft"

    init() {
        // Read before adding tabs: adding the first one selects it, which saves 0.
        let pane = UserDefaults.standard.integer(forKey: SettingsTabs.paneKey)
        let tabs = SettingsTabs()
        tabs.tabStyle = .toolbar
        tabs.addTabViewItem(Self.tab("General", "gearshape", GeneralSettings()))
        tabs.addTabViewItem(Self.tab("Appearance", "paintbrush", AppearanceSettings()))
        tabs.addTabViewItem(Self.tab("Window", "macwindow", WindowSettings()))
        tabs.selectedTabViewItemIndex = tabs.tabViewItems.indices.contains(pane) ? pane : 0

        let window = NSWindow(contentViewController: tabs)
        window.toolbarStyle = .preference
        // Sized by its pane and quick to reopen with ⌘,: no zoom or minimise.
        window.styleMask.subtract([.resizable, .miniaturizable])
        window.isReleasedWhenClosed = false
        // Opens on the current Space instead of following you to every one.
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        super.init(window: window)
        window.delegate = self
        placeWindow()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// The top-left corner is kept, not the frame: the height depends on the pane.
    private func placeWindow() {
        guard let window else { return }
        if let saved = UserDefaults.standard.string(forKey: Self.positionKey) {
            let topLeft = NSPointFromString(saved)
            // Only if that spot is still on a screen (displays can change).
            let inside = NSPoint(x: topLeft.x + 40, y: topLeft.y - 20)
            if NSScreen.screens.contains(where: { $0.visibleFrame.contains(inside) }) {
                window.setFrameTopLeftPoint(topLeft)
                return
            }
        }
        window.center()
    }

    func windowDidMove(_ notification: Notification) {
        guard let frame = window?.frame else { return }
        UserDefaults.standard.set(NSStringFromPoint(NSPoint(x: frame.minX, y: frame.maxY)), forKey: Self.positionKey)
    }

    private static func tab(_ title: String, _ symbol: String, _ view: some View) -> NSTabViewItem {
        let host = NSHostingController(rootView: view.frame(width: 480).fixedSize(horizontal: false, vertical: true))
        host.sizingOptions = .preferredContentSize
        host.title = title
        let item = NSTabViewItem(viewController: host)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        return item
    }
}
