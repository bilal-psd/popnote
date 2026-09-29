import AppKit
import Carbon
import PopnoteCore
import ServiceManagement
import SwiftUI

private typealias Key = PopnoteCore.Settings.Key

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            AppearanceSettings().tabItem { Label("Appearance", systemImage: "paintbrush") }
            WindowSettings().tabItem { Label("Window", systemImage: "macwindow") }
            KeywordSettings().tabItem { Label("Keywords", systemImage: "textformat") }
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .font(Font(Fonts.mono(12) as CTFont))
    }
}

// MARK: General

private struct GeneralSettings: View {
    @AppStorage(Key.expiryHours) private var expiryHours = PopnoteCore.Settings.Default.expiryHours
    @AppStorage(Key.trashDays) private var trashDays = PopnoteCore.Settings.Default.trashDays
    @AppStorage(Key.checkedItems) private var checkedItems = CheckedBehavior.keep.rawValue
    @AppStorage(Key.obsidianVault) private var obsidianVault = ""
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
                LabeledContent("Open Popnote from anywhere") { HotkeyRecorder() }
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            } footer: {
                Text("To change other shortcuts, add them for Popnote in System Settings › Keyboard › Keyboard Shortcuts › App Shortcuts, using the menu item's name.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Export") {
                TextField("Obsidian vault", text: $obsidianVault, prompt: Text("The vault that's open"))
            }
        }
        .formStyle(.grouped)
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
            Picker("Theme", selection: $theme) {
                ForEach(Theme.all, id: \.id) { Text($0.name).tag($0.id) }
            }
            Picker("Font", selection: $font) {
                Text("Auto (Nerd Font if installed)").tag("")
                ForEach(Fonts.installedMonospaced, id: \.self) { Text($0).tag($0) }
            }
            if !Fonts.hasNerdGlyphs {
                Text("Install a Nerd Font (e.g. brew install --cask font-jetbrains-mono-nerd-font) for icons and powerline separators.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Picker("Paper", selection: $paper) {
                ForEach(Paper.allCases, id: \.rawValue) { Text($0.name).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            LabeledContent("Text size") {
                HStack {
                    Slider(value: $textSize, in: 11...22, step: 1)
                    Text("\(Int(textSize)) pt").monospacedDigit().frame(width: 40, alignment: .trailing)
                }
            }
            Toggle("Translucent window", isOn: $translucent)
        }
        .formStyle(.grouped)
    }
}

// MARK: Window

private struct WindowSettings: View {
    @AppStorage(Key.showInMenuBar) private var showInMenuBar = true
    @AppStorage(Key.showInDock) private var showInDock = false
    @AppStorage(Key.dropdown) private var dropdown = false
    @AppStorage(Key.keepOnTop) private var keepOnTop = false
    @AppStorage(Key.hotkeyLabel) private var hotkeyLabel = PopnoteCore.Settings.Default.hotkeyLabel

    var body: some View {
        Form {
            Section {
                Toggle("Show in menu bar", isOn: $showInMenuBar)
                Toggle("Show in Dock", isOn: $showInDock)
                if !showInMenuBar && !showInDock {
                    Text("Popnote will only open with \(hotkeyLabel).").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                Toggle("Drop down from the menu bar", isOn: $dropdown)
                Text("Opens under the menu bar icon and hides when you click elsewhere.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Keep on top of other windows", isOn: $keepOnTop)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Keywords

private struct KeywordSettings: View {
    @AppStorage(Key.keywordList) private var list = ""
    @AppStorage(Key.keywordCode) private var code = ""
    @AppStorage(Key.keywordPin) private var pin = ""
    @AppStorage(Key.keywordCheck) private var check = ""

    var body: some View {
        Form {
            Section {
                TextField("Checklist note", text: $list, prompt: Text(Keywords.standard.list))
                TextField("Code note", text: $code, prompt: Text(Keywords.standard.code))
                TextField("Pinned note", text: $pin, prompt: Text(Keywords.standard.pin))
            } header: {
                Text("First line of a note")
            }
            Section {
                TextField("Check off an item", text: $check, prompt: Text(Keywords.standard.check))
            } header: {
                Text("End of a checklist item")
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

    var body: some View {
        Button(monitor == nil ? label : "Type shortcut…") {
            monitor == nil ? start() : stop()
        }
        .frame(minWidth: 110)
    }

    private func start() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { (event: NSEvent) -> NSEvent? in
            if event.keyCode == UInt16(kVK_Escape) {
                stop()
                return nil
            }
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !flags.intersection([.command, .option, .control]).isEmpty else {
                NSSound.beep()
                return nil
            }
            keyCode = Int(event.keyCode)
            modifiers = carbonModifiers(flags)
            label = symbols(flags) + keyName(event)
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
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

final class SettingsWindowController: NSWindowController {
    init() {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
        window.title = "Popnote Settings"
        window.styleMask.remove(.resizable)
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }
}
