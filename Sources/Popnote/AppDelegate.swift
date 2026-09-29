import AppKit
import PopnoteCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var store: NoteStore!
    private var panel: NotePanel!
    private var noteController: NoteViewController!
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var trashWindow: TrashWindowController?
    private var settingsWindow: SettingsWindowController?
    private var sweepTimer: Timer?

    /// The settings as last applied, so unrelated defaults writes are ignored.
    private struct Applied: Equatable {
        var theme = "", paper = "", font: String? = nil, textSize = 0.0, translucent = false
        var showInDock = false, showInMenuBar = false, keepOnTop = false
        var hotkeyKeyCode = -1, hotkeyModifiers = -1
        var keywords = Keywords.standard
    }
    private var applied: Applied?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            store = try NoteStore(url: NoteStore.defaultURL())
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Popnote couldn't open its notes database."
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        sweep()

        noteController = NoteViewController(store: store)
        noteController.onHide = { [weak self] in self?.hidePanel() }
        noteController.onOpenSettings = { [weak self] in self?.showSettings(nil) }
        noteController.appCommands = { [weak self] in self?.appCommands() ?? [] }
        panel = NotePanel(contentViewController: noteController)
        panel.delegate = self
        NSApp.mainMenu = makeMainMenu()
        setUpStatusItem()
        applySettings()
        NotificationCenter.default.addObserver(
            self, selector: #selector(applySettings), name: UserDefaults.didChangeNotification, object: nil)

        // Expire notes once a minute, and right after the Mac wakes.
        sweepTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.sweep() }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(sweep), name: NSWorkspace.didWakeNotification, object: nil)

        showPanel()
    }

    /// Clicking the Dock icon (when shown) opens the panel.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return true
    }

    @objc private func sweep() {
        _ = try? store.sweep(ttl: Settings.noteTTL, trashRetention: Settings.trashRetention)
        noteController?.refresh()
        trashWindow?.model.reload()
    }

    // MARK: Settings

    @objc private func applySettings() {
        let now = Applied(theme: Settings.theme, paper: Settings.paper, font: Settings.font, textSize: Settings.textSize,
                          translucent: Settings.translucent, showInDock: Settings.showInDock,
                          showInMenuBar: Settings.showInMenuBar, keepOnTop: Settings.keepOnTop,
                          hotkeyKeyCode: Settings.hotkeyKeyCode, hotkeyModifiers: Settings.hotkeyModifiers,
                          keywords: Settings.keywords)
        guard now != applied else { return }
        let previous = applied
        applied = now

        noteController.applyAppearance(theme: Theme.named(now.theme), paper: Paper(rawValue: now.paper) ?? .blank,
                                       fontSize: CGFloat(now.textSize), translucent: now.translucent)
        panel.isOpaque = !now.translucent
        panel.backgroundColor = now.translucent ? .clear : Theme.named(now.theme).background
        panel.level = now.keepOnTop ? .floating : .normal
        statusItem.isVisible = now.showInMenuBar

        if now.showInDock != previous?.showInDock {
            NSApp.setActivationPolicy(now.showInDock ? .regular : .accessory)
            if previous != nil { showPanel() } // switching policy can deactivate the app
        }
        if now.hotkeyKeyCode != previous?.hotkeyKeyCode || now.hotkeyModifiers != previous?.hotkeyModifiers {
            hotKey = nil // unregister the old one first
            hotKey = HotKey(keyCode: now.hotkeyKeyCode, modifiers: now.hotkeyModifiers) { [weak self] in
                self?.togglePanel()
            }
            if hotKey == nil { NSLog("Popnote: \(Settings.hotkeyLabel) is taken by another app; hotkey not registered") }
        }
    }

    /// Palette commands that live at the app level.
    private func appCommands() -> [Command] {
        var commands = [
            Command("Open trash", "⌘⇧⌫") { [weak self] in self?.showTrash(nil) },
            Command("Settings", "⌘,") { [weak self] in self?.showSettings(nil) },
            Command("Bigger text", "⌘=") { [weak self] in self?.biggerText(nil) },
            Command("Smaller text", "⌘-") { [weak self] in self?.smallerText(nil) },
            Command("Close window", "esc") { [weak self] in self?.hidePanel() },
            Command("Quit Popnote", "⌘Q") { NSApp.terminate(nil) },
        ]
        for theme in Theme.all where theme.id != Settings.theme {
            commands.append(Command("Theme: \(theme.name)") {
                UserDefaults.standard.set(theme.id, forKey: Settings.Key.theme)
            })
        }
        for paper in Paper.allCases where paper.rawValue != Settings.paper {
            commands.append(Command("Paper: \(paper.name.lowercased())") {
                UserDefaults.standard.set(paper.rawValue, forKey: Settings.Key.paper)
            })
        }
        commands.append(Command(Settings.translucent ? "Make window opaque" : "Make window translucent") {
            UserDefaults.standard.set(!Settings.translucent, forKey: Settings.Key.translucent)
        })
        return commands
    }

    @objc func biggerText(_ sender: Any?) { setTextSize(Settings.textSize + 1) }
    @objc func smallerText(_ sender: Any?) { setTextSize(Settings.textSize - 1) }

    private func setTextSize(_ size: Double) {
        UserDefaults.standard.set(min(max(size, 10), 24), forKey: Settings.Key.textSize)
    }

    @objc func showSettings(_ sender: Any?) {
        if settingsWindow == nil { settingsWindow = SettingsWindowController() }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.showWindow(nil)
    }

    // MARK: Panel

    @objc func togglePanel() {
        if panel.isVisible && NSApp.isActive {
            hidePanel()
        } else {
            showPanel()
        }
    }

    @objc func showPanel() {
        if Settings.dropdown && !panel.isVisible { positionAsDropdown() }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        noteController.focusEditor()
    }

    /// Hides the panel and hands focus back to the previous app.
    @objc func hidePanel() {
        panel.orderOut(nil)
        if settingsWindow?.window?.isVisible != true && trashWindow?.window?.isVisible != true {
            NSApp.hide(nil)
        }
    }

    /// Dropdown mode: the panel hangs under the menu bar icon, or at the top
    /// of the screen if the icon is hidden.
    private func positionAsDropdown() {
        var frame = panel.frame
        if statusItem.isVisible, let button = statusItem.button, let buttonWindow = button.window {
            let icon = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
            frame.origin = NSPoint(x: icon.midX - frame.width / 2, y: icon.minY - frame.height - 6)
            if let visible = buttonWindow.screen?.visibleFrame {
                frame.origin.x = min(max(frame.minX, visible.minX + 8), visible.maxX - frame.width - 8)
            }
        } else if let visible = NSScreen.main?.visibleFrame {
            frame.origin = NSPoint(x: visible.midX - frame.width / 2, y: visible.maxY - frame.height - 6)
        }
        panel.setFrame(frame, display: false)
    }

    /// Dropdown mode hides the panel when you click elsewhere.
    func windowDidResignKey(_ notification: Notification) {
        guard Settings.dropdown, !Settings.keepOnTop, panel.attachedSheet == nil else { return }
        panel.orderOut(nil)
    }

    @objc func newNoteFromMenuBar(_ sender: Any?) {
        showPanel()
        noteController.newNote(nil)
    }

    @objc func showTrash(_ sender: Any?) {
        if trashWindow == nil {
            let model = TrashModel(store: store) { [weak self] note in
                self?.noteController.reload(keeping: note.id)
                self?.showPanel()
            }
            trashWindow = TrashWindowController(model: model)
        }
        trashWindow?.model.reload()
        NSApp.activate(ignoringOtherApps: true)
        trashWindow?.showWindow(nil)
    }

    // MARK: Menu bar item

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "Popnote")
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    /// Left click toggles the panel; right click shows a small menu.
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard NSApp.currentEvent?.type == .rightMouseUp else {
            togglePanel()
            return
        }
        let menu = NSMenu()
        menu.addItem(item("New Note", #selector(newNoteFromMenuBar(_:)), target: self))
        menu.addItem(item("Trash…", #selector(showTrash(_:)), target: self))
        menu.addItem(item("Settings…", #selector(showSettings(_:)), target: self))
        menu.addItem(.separator())
        menu.addItem(item("Quit Popnote", #selector(NSApplication.terminate(_:)), target: NSApp))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    // MARK: Main menu
    //
    // Visible only when Popnote is in the Dock, but always what makes keyboard
    // shortcuts like ⌘C and ⌘P work while the panel is focused.

    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(item("About Popnote", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), target: NSApp))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Settings…", #selector(showSettings(_:)), ",", target: self))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Hide Popnote", #selector(hidePanel), "h", target: self))
        appMenu.addItem(item("Quit Popnote", #selector(NSApplication.terminate(_:)), "q", target: NSApp))
        addSubmenu(appMenu, to: main)

        let edit = NSMenu(title: "Edit")
        edit.addItem(item("Undo", Selector(("undo:")), "z"))
        edit.addItem(item("Redo", Selector(("redo:")), "Z"))
        edit.addItem(.separator())
        edit.addItem(item("Cut", #selector(NSText.cut(_:)), "x"))
        edit.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        edit.addItem(item("Paste", #selector(NSText.paste(_:)), "v"))
        edit.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a"))
        edit.addItem(.separator())
        edit.addItem(item("Find…", #selector(NoteViewController.toggleSearch(_:)), "f", target: noteController))
        edit.addItem(item("Commands…", #selector(NoteViewController.toggleCommandPalette(_:)), "k", target: noteController))
        addSubmenu(edit, to: main)

        let note = NSMenu(title: "Note")
        let backspace = String(UnicodeScalar(NSBackspaceCharacter)!)
        note.addItem(item("New Note", #selector(NoteViewController.newNote(_:)), "n", target: noteController))
        note.addItem(item("Previous Note", #selector(NoteViewController.previousNote(_:)), "[", target: noteController))
        note.addItem(item("Next Note", #selector(NoteViewController.nextNote(_:)), "]", target: noteController))
        note.addItem(item("Newest Note", #selector(NoteViewController.jumpToNewest(_:)), "0", target: noteController))
        note.addItem(.separator())
        note.addItem(item("Pin / Unpin", #selector(NoteViewController.togglePin(_:)), "p", target: noteController))
        note.addItem(item("Move to Trash", #selector(NoteViewController.deleteNote(_:)), backspace, target: noteController))
        let trash = item("Trash…", #selector(showTrash(_:)), backspace, target: self)
        trash.keyEquivalentModifierMask = [.command, .shift]
        note.addItem(trash)
        note.addItem(.separator())
        note.addItem(item("Copy Note Text", #selector(NoteViewController.copyNoteText(_:)), "C", target: noteController))
        let export = NSMenu(title: "Export")
        export.addItem(item("Save as Text…", #selector(NoteViewController.saveAsText(_:)), target: noteController))
        export.addItem(item("Save as Markdown…", #selector(NoteViewController.saveAsMarkdown(_:)), target: noteController))
        export.addItem(item("Save as PDF…", #selector(NoteViewController.saveAsPDF(_:)), target: noteController))
        export.addItem(.separator())
        export.addItem(item("Send to Apple Notes", #selector(NoteViewController.sendToAppleNotes(_:)), target: noteController))
        export.addItem(item("Send to Obsidian", #selector(NoteViewController.sendToObsidian(_:)), target: noteController))
        export.addItem(item("Send to Bear", #selector(NoteViewController.sendToBear(_:)), target: noteController))
        let exportHolder = NSMenuItem(title: "Export", action: nil, keyEquivalent: "")
        exportHolder.submenu = export
        note.addItem(exportHolder)
        note.addItem(.separator())
        note.addItem(item("Keep on Top", #selector(NoteViewController.toggleKeepOnTop(_:)), "T", target: noteController))
        note.addItem(item("Close", #selector(hidePanel), "w", target: self))
        addSubmenu(note, to: main)

        // Sent to the focused editor (nil target = first responder).
        let format = NSMenu(title: "Format")
        format.addItem(item("Check / Uncheck", #selector(EditorTextView.toggleCheckbox(_:)), "\r"))
        format.addItem(.separator())
        format.addItem(item("Bigger", #selector(biggerText(_:)), "=", target: self))
        format.addItem(item("Smaller", #selector(smallerText(_:)), "-", target: self))
        addSubmenu(format, to: main)

        return main
    }

    private func item(_ title: String, _ action: Selector, _ key: String = "", target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target
        return item
    }

    private func addSubmenu(_ menu: NSMenu, to main: NSMenu) {
        let holder = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        holder.submenu = menu
        main.addItem(holder)
    }
}
