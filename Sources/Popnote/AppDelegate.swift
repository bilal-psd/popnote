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
        noteController.onOpenTrash = { [weak self] in self?.showTrash(nil) }
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
            registerHotKey(keyCode: now.hotkeyKeyCode, modifiers: now.hotkeyModifiers)
        }
    }

    /// Swaps in a new global hotkey. If it can't be registered (another app
    /// holds it), the one that was working stays.
    private func registerHotKey(keyCode: Int, modifiers: Int) {
        hotKey = nil // unregister the old one first; re-registering the same keys would fail
        let make = { HotKey(keyCode: $0, modifiers: $1) { [weak self] in self?.togglePanel() } }
        if let new = make(keyCode, modifiers) {
            hotKey = new
            hotKeyInUse = (keyCode, modifiers)
            return
        }
        NSLog("Popnote: shortcut \(keyCode)/\(modifiers) is taken by another app; keeping the previous one")
        if let inUse = hotKeyInUse { hotKey = make(inUse.keyCode, inUse.modifiers) }
    }

    /// Keys of the hotkey that's actually registered.
    private var hotKeyInUse: (keyCode: Int, modifiers: Int)?

    @objc func biggerText(_ sender: Any?) { setTextSize(Settings.textSize + 1) }
    @objc func smallerText(_ sender: Any?) { setTextSize(Settings.textSize - 1) }

    private func setTextSize(_ size: Double) {
        let range = Settings.textSizeRange
        UserDefaults.standard.set(min(max(size, range.lowerBound), range.upperBound), forKey: Settings.Key.textSize)
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
        let wasVisible = panel.isVisible
        // Also when the panel stayed up (kept on top) while another app was in
        // front: esc should go back to that app, not the one from last time.
        if !wasVisible || !NSApp.isActive { rememberPreviousApp() }
        if !wasVisible { positionPanel() }
        NSApp.activate(ignoringOtherApps: true)
        if !wasVisible && Settings.animateWindow {
            animateIn()
        } else {
            cancelHide()
            panel.makeKeyAndOrderFront(nil)
        }
        noteController.focusEditor()
    }

    /// Hides the panel and hands focus back to the previous app.
    ///
    /// Focus goes back *before* the fade-out, so anything typed straight after
    /// esc/⌥P lands in that app, not in the fading window.
    @objc func hidePanel() {
        let otherWindowsOpen = settingsWindow?.window?.isVisible == true || trashWindow?.window?.isVisible == true
        if !otherWindowsOpen, let previousApp, !previousApp.isTerminated {
            previousApp.activate()
            dismissPanel()
        } else {
            dismissPanel { if !otherWindowsOpen { NSApp.hide(nil) } }
        }
    }

    // MARK: Opening and closing animation

    /// The app that was frontmost when the panel opened; it gets focus back on close.
    private var previousApp: NSRunningApplication?

    private func rememberPreviousApp() {
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
    }

    /// Bumped by every show/hide so a finished fade-out can tell it was superseded.
    private var animationGeneration = 0
    /// True while fading out; a second hide request (e.g. from losing focus) is ignored.
    private var isHiding = false

    /// Fades the window in while its contents slide ~10pt into place (up from
    /// below, or down under the menu bar). The window itself doesn't move, so
    /// nothing goes through the window server and the saved frame is never off.
    /// With Reduce Motion on, it only fades.
    private func animateIn() {
        animationGeneration += 1
        isHiding = false
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)

        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let content = panel.contentView {
            content.wantsLayer = true
            let slide = CABasicAnimation(keyPath: "transform.translation.y")
            // Layer y points up: start below (or above, for the menu bar) and settle at 0.
            slide.fromValue = Settings.windowPosition == .menuBar ? 10 : -10
            slide.toValue = 0
            slide.duration = 0.12
            slide.timingFunction = Motion.easeOut
            content.layer?.add(slide, forKey: "popnote.open")
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = Motion.easeOut
            panel.animator().alphaValue = 1
        }
    }

    /// Fades out (if animating), then orders the panel out.
    private func dismissPanel(then completion: (() -> Void)? = nil) {
        guard panel.isVisible, !isHiding else { return }
        guard Settings.animateWindow else {
            panel.orderOut(nil)
            completion?()
            return
        }
        animationGeneration += 1
        isHiding = true
        let generation = animationGeneration
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.09
            context.timingFunction = Motion.easeOut
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, generation == self.animationGeneration else { return }
            self.isHiding = false
            self.panel.orderOut(nil)
            self.panel.alphaValue = 1
            completion?()
        })
    }

    /// Reopened mid-fade: keep the window and make it fully visible again.
    private func cancelHide() {
        animationGeneration += 1
        isHiding = false
        panel.alphaValue = 1
    }

    /// Places the panel according to the "Open at" setting.
    private func positionPanel() {
        switch Settings.windowPosition {
        case .remember:
            break
        case .menuBar:
            positionAsDropdown()
        case .bottomRight:
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
            guard let visible = screen?.visibleFrame else { return }
            var frame = panel.frame
            frame.origin = NSPoint(x: visible.maxX - frame.width - 16, y: visible.minY + 16)
            panel.setFrame(frame, display: false)
        }
    }

    /// Under the menu bar icon, or at the top
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

    /// Clicking another app or the desktop hides the panel. Popnote's own
    /// Settings and Trash windows don't count, since they keep the app active.
    func applicationDidResignActive(_ notification: Notification) {
        guard Settings.hideOnClickOutside, !Settings.keepOnTop, panel.attachedSheet == nil else { return }
        dismissPanel()
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
        addSubmenu(edit, to: main)

        let note = NSMenu(title: "Note")
        let backspace = String(UnicodeScalar(NSBackspaceCharacter)!)
        note.addItem(item("All Notes…", #selector(NoteViewController.toggleNotesDrawer(_:)), "o", target: noteController))
        note.addItem(item("New Note", #selector(NoteViewController.newNote(_:)), "n", target: noteController))
        note.addItem(item("Previous Note", #selector(NoteViewController.previousNote(_:)), "[", target: noteController))
        note.addItem(item("Next Note", #selector(NoteViewController.nextNote(_:)), "]", target: noteController))
        note.addItem(item("Newest Note", #selector(NoteViewController.jumpToNewest(_:)), "0", target: noteController))
        note.addItem(.separator())
        note.addItem(item("Pin / Unpin", #selector(NoteViewController.togglePin(_:)), "p", target: noteController))
        note.addItem(item("Move to Trash", #selector(NoteViewController.deleteNote(_:)), backspace, target: noteController))
        note.addItem(item("Trash…", #selector(showTrash(_:)), target: self))
        note.addItem(.separator())
        note.addItem(.separator())
        note.addItem(item("Keep on Top", #selector(NoteViewController.toggleKeepOnTop(_:)), "t", target: noteController))
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
