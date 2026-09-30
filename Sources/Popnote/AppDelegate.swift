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
    private var welcomeWindow: WelcomeWindowController?
    private var sweepTimer: Timer?
    private var reminderTimer: Timer?

    /// The settings as last applied, so unrelated defaults writes are ignored.
    private struct Applied: Equatable {
        var theme = "", paper = "", font: String? = nil, textSize = 0.0, translucent = false
        var showInDock = false, showInMenuBar = false, keepOnTop = false
        var hotkeyKeyCode = -1, hotkeyModifiers = -1
        var reminderEnabled = false, reminderInterval = 0.0
    }
    private var applied: Applied?

    func applicationDidFinishLaunching(_ notification: Notification) {
        LegacyDefaults.migrate()
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

        if WelcomeWindowController.hasBeenSeen {
            showPanel()
        } else {
            welcomeWindow = WelcomeWindowController { [weak self] in
                self?.welcomeWindow = nil
                self?.showPanel()
            }
            NSApp.activate(ignoringOtherApps: true)
            welcomeWindow?.showWindow(nil)
        }
    }

    /// Clicking the Dock icon (when shown) opens the panel.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return true
    }

    @objc private func sweep() {
        // Nothing expires until notes pinned by a "pin" first line have the flag.
        guard convertKeywordLines() else { return }
        _ = try? store.sweep(ttl: Settings.noteTTL, trashRetention: Settings.trashRetention)
        noteController?.refresh()
        trashWindow?.model.reload()
    }

    /// One-time upgrade from first-line keywords. False if it failed; it's
    /// retried on the next sweep.
    private func convertKeywordLines() -> Bool {
        guard let keywords = Settings.legacyKeywords else { return true }
        guard (try? store.convertKeywordLines(pin: keywords.pin, keywords: keywords.all)) != nil else { return false }
        Settings.removeKeywords()
        return true
    }

    // MARK: Settings

    @objc private func applySettings() {
        let now = Applied(theme: Settings.theme, paper: Settings.paper, font: Settings.font, textSize: Settings.textSize,
                          translucent: Settings.translucent, showInDock: Settings.showInDock,
                          showInMenuBar: Settings.showInMenuBar, keepOnTop: Settings.keepOnTop,
                          hotkeyKeyCode: Settings.hotkeyKeyCode, hotkeyModifiers: Settings.hotkeyModifiers,
                          reminderEnabled: Settings.reminderEnabled, reminderInterval: Settings.reminderInterval)
        guard now != applied else { return }
        let previous = applied
        applied = now

        noteController.applyAppearance(theme: Theme.named(now.theme), paper: Paper(rawValue: now.paper) ?? .blank,
                                       fontSize: CGFloat(now.textSize), translucent: now.translucent)
        panel.isOpaque = !now.translucent
        panel.backgroundColor = now.translucent ? .clear : Theme.named(now.theme).background
        panel.level = now.keepOnTop ? .floating : .normal
        panel.setFollowsAllSpaces(now.keepOnTop)
        statusItem.isVisible = now.showInMenuBar

        if now.showInDock != previous?.showInDock {
            NSApp.setActivationPolicy(now.showInDock ? .regular : .accessory)
            if previous != nil { showPanel() } // switching policy can deactivate the app
        }
        if now.hotkeyKeyCode != previous?.hotkeyKeyCode || now.hotkeyModifiers != previous?.hotkeyModifiers {
            scheduleHotKeyUpdate()
        }
        if now.reminderEnabled != previous?.reminderEnabled || now.reminderInterval != previous?.reminderInterval {
            // Counts from now; while the panel is open it waits for it to close.
            if panel.isVisible { reminderTimer?.invalidate() } else { scheduleReminder() }
        }
    }

    /// Starts the countdown to popping the panel back up, if the reminder is on.
    private func scheduleReminder() {
        reminderTimer?.invalidate()
        reminderTimer = nil
        guard Settings.reminderEnabled else { return }
        reminderTimer = Timer.scheduledTimer(withTimeInterval: Settings.reminderInterval, repeats: false) { [weak self] _ in
            guard let self else { return }
            showPanel()
            // Only here: opening it yourself needs no fanfare.
            GlowWindow.flash(around: panel, color: Theme.named(Settings.theme).accent)
        }
    }

    private var hotKeyUpdatePending = false

    /// The recorder saves the key code, modifiers and label one at a time;
    /// register once they're all in, not each half-changed combination.
    private func scheduleHotKeyUpdate() {
        guard !hotKeyUpdatePending else { return }
        hotKeyUpdatePending = true
        DispatchQueue.main.async { [self] in
            hotKeyUpdatePending = false
            registerHotKey(keyCode: Settings.hotkeyKeyCode, modifiers: Settings.hotkeyModifiers)
        }
    }

    /// Swaps in a new global hotkey. If it can't be registered (rare: only when
    /// another app claimed the keys exclusively), the one that was working
    /// stays (the default at launch), and Settings is put back to match it.
    private func registerHotKey(keyCode: Int, modifiers: Int) {
        if let inUse = hotKeyInUse, inUse.keyCode == keyCode, inUse.modifiers == modifiers, hotKey != nil { return }
        hotKey = nil // unregister the old one first; re-registering the same keys would fail
        let make = { HotKey(keyCode: $0, modifiers: $1) { [weak self] in self?.togglePanel() } }
        if let new = make(keyCode, modifiers) {
            hotKey = new
            hotKeyInUse = (keyCode, modifiers, Settings.hotkeyLabel)
            return
        }
        NSLog("Popnote: couldn't register shortcut \(keyCode)/\(modifiers); keeping the previous one")
        let fallback = hotKeyInUse
            ?? (Settings.Default.hotkeyKeyCode, Settings.Default.hotkeyModifiers, Settings.Default.hotkeyLabel)
        guard fallback.keyCode != keyCode || fallback.modifiers != modifiers,
              let restored = make(fallback.keyCode, fallback.modifiers) else { return }
        hotKey = restored
        hotKeyInUse = fallback
        // Mark it applied first, so the writes below don't register it again.
        applied?.hotkeyKeyCode = fallback.keyCode
        applied?.hotkeyModifiers = fallback.modifiers
        let defaults = UserDefaults.standard
        defaults.set(fallback.keyCode, forKey: Settings.Key.hotkeyKeyCode)
        defaults.set(fallback.modifiers, forKey: Settings.Key.hotkeyModifiers)
        defaults.set(fallback.label, forKey: Settings.Key.hotkeyLabel)
    }

    /// The hotkey that's actually registered.
    private var hotKeyInUse: (keyCode: Int, modifiers: Int, label: String)?

    @objc func biggerText(_ sender: Any?) { setTextSize(Settings.textSize + 1) }
    @objc func smallerText(_ sender: Any?) { setTextSize(Settings.textSize - 1) }

    private func setTextSize(_ size: Double) {
        let range = Settings.textSizeRange
        UserDefaults.standard.set(min(max(size, range.lowerBound), range.upperBound), forKey: Settings.Key.textSize)
    }

    /// The standard About panel stays on the Space it opened on; left open,
    /// it made every activation (opening the note) switch to that Space.
    @objc func showAbout(_ sender: Any?) {
        let existing = Set(NSApp.windows.map(ObjectIdentifier.init))
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(sender)
        // AppKit creates the panel on first use; it's the one window that's new.
        for window in NSApp.windows where !existing.contains(ObjectIdentifier(window)) {
            window.collectionBehavior.insert(.moveToActiveSpace)
        }
    }

    @objc func showSettings(_ sender: Any?) {
        if settingsWindow == nil { settingsWindow = SettingsWindowController() }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.showWindow(nil)
    }

    // MARK: Panel

    /// Kept on top, the panel is in sight even while another app is in front,
    /// so the shortcut closes it rather than focusing it.
    @objc func togglePanel() {
        if panel.isVisible && (NSApp.isActive || Settings.keepOnTop) {
            hidePanel()
        } else {
            showPanel()
        }
    }

    @objc func showPanel() {
        reminderTimer?.invalidate() // restarts when the panel closes
        let wasVisible = panel.isVisible
        // Also when it's already up but another app is in front (clicking a kept-
        // on-top panel, the reminder, New Note): esc goes back to that app.
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
        // Closed from another app (kept on top): focus is already where it belongs.
        guard NSApp.isActive else { return dismissPanel() }
        let otherWindowsOpen = settingsWindow?.window?.isVisible == true || trashWindow?.window?.isVisible == true
        // Only if it's on this Space: activating it would switch to its Space.
        if !otherWindowsOpen, let previousApp, !previousApp.isTerminated, hasWindowOnCurrentSpace(previousApp) {
            previousApp.activate()
            dismissPanel()
        } else {
            dismissPanel { if !otherWindowsOpen { NSApp.hide(nil) } }
        }
    }

    /// Whether `app` has a normal window on the current Space. Owner and layer
    /// need no screen recording permission, unlike window titles.
    private func hasWindowOnCurrentSpace(_ app: NSRunningApplication) -> Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return true }
        return windows.contains {
            ($0[kCGWindowOwnerPID as String] as? pid_t) == app.processIdentifier
                && ($0[kCGWindowLayer as String] as? Int) == 0
        }
    }

    /// ⌘W closes whichever window is in front: Settings, Trash or the panel.
    @objc func closeWindow(_ sender: Any?) {
        if let window = NSApp.keyWindow, window !== panel {
            window.performClose(sender)
        } else {
            hidePanel()
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
        scheduleReminder()
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

    /// Unless kept on top, the panel hides as soon as Popnote loses focus:
    /// clicking another app or the desktop, ⌘Tab, or switching Spaces. It
    /// stays on the Space you left, so it fades out there, out of sight.
    /// Popnote's own Settings and Trash windows don't count, since they keep
    /// the app active.
    func applicationDidResignActive(_ notification: Notification) {
        // Leaving Popnote starts the pop-up countdown, even when the panel
        // stays open behind other windows or the app was hidden from the
        // Dock. A panel kept on top is still in sight, so it doesn't count.
        guard let panel else { return } // the database failed to open; quitting
        if !(panel.isVisible && Settings.keepOnTop) { scheduleReminder() }
        guard !Settings.keepOnTop, panel.attachedSheet == nil else { return }
        dismissPanel()
    }

    /// Back in the panel (e.g. clicking it behind other windows): no need to pop it up.
    func applicationDidBecomeActive(_ notification: Notification) {
        if panel?.isVisible == true { reminderTimer?.invalidate() }
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
        // Drawn by scripts/icon.swift; the SF Symbol covers `swift run`, which has no bundle.
        let icon = Bundle.main.image(forResource: "MenuBarIcon")
            ?? NSImage(systemSymbolName: "note.text", accessibilityDescription: "Popnote")
        icon?.isTemplate = true
        icon?.accessibilityDescription = "Popnote"
        statusItem.button?.image = icon
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
        appMenu.addItem(item("About Popnote", #selector(showAbout(_:)), target: self))
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
        addSubmenu(edit, to: main)

        let note = NSMenu(title: "Note")
        let backspace = String(UnicodeScalar(NSBackspaceCharacter)!)
        note.addItem(item("All Notes…", #selector(NoteViewController.toggleNotesDrawer(_:)), "o", target: noteController))
        note.addItem(item("New Note", #selector(NoteViewController.newNote(_:)), "n", target: noteController))
        note.addItem(item("Previous Note", #selector(NoteViewController.previousNote(_:)), "[", target: noteController))
        note.addItem(item("Next Note", #selector(NoteViewController.nextNote(_:)), "]", target: noteController))
        note.addItem(.separator())
        note.addItem(item("Pin / Unpin", #selector(NoteViewController.togglePin(_:)), "p", target: noteController))
        note.addItem(item("Move to Trash", #selector(NoteViewController.deleteNote(_:)), backspace, target: noteController))
        note.addItem(item("Trash…", #selector(showTrash(_:)), target: self))
        note.addItem(.separator())
        note.addItem(.separator())
        note.addItem(item("Keep on Top", #selector(NoteViewController.toggleKeepOnTop(_:)), "t", target: noteController))
        note.addItem(item("Pop Up on a Timer", #selector(NoteViewController.toggleReminder(_:)), "r", target: noteController))
        note.addItem(item("Close", #selector(closeWindow(_:)), "w", target: self))
        addSubmenu(note, to: main)

        // Sent to the focused editor (nil target = first responder).
        let format = NSMenu(title: "Format")
        format.addItem(item("Check / Uncheck", #selector(EditorTextView.toggleCheckbox(_:)), "\r"))
        format.addItem(.separator())
        format.addItem(item("Bigger", #selector(biggerText(_:)), "+", target: self))
        // "+" is ⇧= on US keyboards, so plain ⌘= works too, as in Safari.
        let equals = item("Bigger", #selector(biggerText(_:)), "=", target: self)
        equals.isHidden = true
        equals.allowsKeyEquivalentWhenHidden = true
        format.addItem(equals)
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
