import AppKit
import Carbon
import PopnoteCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: NoteStore!
    private var panel: NotePanel!
    private var noteController: NoteViewController!
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var voidWindow: VoidWindowController?
    private var sweepTimer: Timer?

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
        panel = NotePanel(contentViewController: noteController)
        NSApp.mainMenu = makeMainMenu()
        setUpStatusItem()

        hotKey = HotKey(keyCode: kVK_ANSI_A, modifiers: optionKey) { [weak self] in self?.togglePanel() }
        if hotKey == nil { NSLog("Popnote: ⌥A is taken by another app; hotkey not registered") }

        // Expire notes once a minute, and right after the Mac wakes.
        sweepTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.sweep() }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(sweep), name: NSWorkspace.didWakeNotification, object: nil)

        showPanel()
    }

    @objc private func sweep() {
        _ = try? store.sweep(ttl: Settings.noteTTL, voidRetention: Settings.voidRetention)
        noteController?.refresh()
        voidWindow?.model.reload()
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
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        noteController.focusEditor()
    }

    /// Hides the panel and hands focus back to the previous app.
    @objc func hidePanel() {
        panel.orderOut(nil)
        NSApp.hide(nil)
    }

    @objc func newNoteFromMenuBar(_ sender: Any?) {
        showPanel()
        noteController.newNote(nil)
    }

    @objc func showVoid(_ sender: Any?) {
        if voidWindow == nil {
            let model = VoidModel(store: store) { [weak self] note in
                self?.noteController.reload(keeping: note.id)
                self?.showPanel()
            }
            voidWindow = VoidWindowController(model: model)
        }
        voidWindow?.model.reload()
        NSApp.activate(ignoringOtherApps: true)
        voidWindow?.showWindow(nil)
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
        menu.addItem(item("The Void…", #selector(showVoid(_:)), target: self))
        menu.addItem(.separator())
        menu.addItem(item("Quit Popnote", #selector(NSApplication.terminate(_:)), target: NSApp))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    // MARK: Main menu
    //
    // Never visible (Popnote has no dock icon), but it's what makes keyboard
    // shortcuts like ⌘C and ⌘P work while the panel is focused.

    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
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
        addSubmenu(edit, to: main)

        let note = NSMenu(title: "Note")
        let backspace = String(UnicodeScalar(NSBackspaceCharacter)!)
        note.addItem(item("New Note", #selector(NoteViewController.newNote(_:)), "n", target: noteController))
        note.addItem(item("Previous Note", #selector(NoteViewController.previousNote(_:)), "[", target: noteController))
        note.addItem(item("Next Note", #selector(NoteViewController.nextNote(_:)), "]", target: noteController))
        note.addItem(item("Newest Note", #selector(NoteViewController.jumpToNewest(_:)), "0", target: noteController))
        note.addItem(.separator())
        note.addItem(item("Pin / Unpin", #selector(NoteViewController.togglePin(_:)), "p", target: noteController))
        note.addItem(item("Move to The Void", #selector(NoteViewController.deleteNote(_:)), backspace, target: noteController))
        let void = item("The Void…", #selector(showVoid(_:)), backspace, target: self)
        void.keyEquivalentModifierMask = [.command, .shift]
        note.addItem(void)
        note.addItem(.separator())
        note.addItem(item("Close", #selector(hidePanel), "w", target: self))
        addSubmenu(note, to: main)

        // Sent to the focused editor (nil target = first responder).
        let format = NSMenu(title: "Format")
        let cycle = item("Cycle Line Type", #selector(EditorTextView.cycleLineType(_:)), "m")
        cycle.keyEquivalentModifierMask = [.command, .shift]
        format.addItem(cycle)
        format.addItem(item("Check / Uncheck", #selector(EditorTextView.toggleCheckbox(_:)), "\r"))
        addSubmenu(format, to: main)

        return main
    }

    private func item(_ title: String, _ action: Selector, _ key: String = "", target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target
        return item
    }

    private func addSubmenu(_ menu: NSMenu, to main: NSMenu) {
        let holder = NSMenuItem()
        holder.submenu = menu
        main.addItem(holder)
    }
}
