import AppKit
import PopnoteCore

/// One note at a time: the editor, the note's position in the bottom-right
/// corner, a "/" search prompt, the ⌘O notes drawer, and a shortcut list
/// shown while ⌘ is held.
/// Everything is reachable by keyboard.
///
/// Notes are ordered oldest → newest. `index == notes.count` is the blank
/// draft past the newest note; it only becomes a real note once you type.
final class NoteViewController: NSViewController, NSTextViewDelegate, NSTextFieldDelegate, NSMenuItemValidation {
    var onHide: (() -> Void)?
    var onOpenTrash: (() -> Void)?

    private let store: NoteStore
    private var notes: [Note] = []
    private var index = 0
    /// Pin pressed on the blank draft; applied when the note is created.
    private var draftPinned = false
    /// The editor holds text the store refused. Nothing may replace it until
    /// a save succeeds.
    private var hasUnsavedEdits = false

    private let effectView = NSVisualEffectView()
    private let backgroundView = BackgroundView()
    private let scrollView = SwipeScrollView()
    /// Starts at zero width: it only follows the scroll view's *changes* in
    /// width, so any starting width would stay added on and lines would wrap
    /// off the right edge.
    private let textView = EditorTextView(frame: .zero)
    private let searchBar = SearchBarView()
    private let cornerInfo = CornerInfoView()
    private let shortcuts = ShortcutOverlayView()
    private var shortcutTimer: Timer?
    private var keyMonitor: Any?
    private let drawer = NotesDrawerView()
    private let scrim = ScrimView()
    private var theme = Theme.all[0]

    private lazy var swipe = SwipeTransition(target: scrollView)
    /// Reduce Motion fallback: the note switches once the swipe passes a threshold.
    private var swipeFired = false

    private var searchMatchIDs: [Int64] = []
    private var searchCursor = 0

    private var current: Note? { index < notes.count ? notes[index] : nil }

    init(store: NoteStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Layout

    override func loadView() {
        // Blurred desktop (seen only when translucent) under the theme colour.
        let root = effectView
        root.frame = NSRect(x: 0, y: 0, width: 400, height: 460)
        root.material = .popover
        root.blendingMode = .behindWindow
        root.state = .active
        backgroundView.frame = root.bounds
        backgroundView.autoresizingMask = [.width, .height]
        root.addSubview(backgroundView)

        textView.configure()
        textView.delegate = self
        textView.onEscape = { [weak self] in self?.onHide?() }
        textView.onCopiedNote = { [weak self] in self?.cornerInfo.flash("copied note") }

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        // The transparent title bar sits over the top of the editor; start below it.
        scrollView.automaticallyAdjustsContentInsets = false
        // Bottom inset keeps the last line clear of the corner indicator.
        scrollView.contentInsets = NSEdgeInsets(top: 14, left: 0, bottom: 24, right: 0)
        scrollView.onSwipeBegan = { [weak self] in self?.swipeBegan() }
        scrollView.onSwipeChanged = { [weak self] travel in self?.swipeChanged(travel) }
        scrollView.onSwipeEnded = { [weak self] velocity in self?.swipeEnded(velocity) }
        swipe.render = { [weak self] in self?.renderForSwipe() ?? (nil, SwipeTransition.Neighbours()) }
        swipe.commit = { [weak self] direction in
            guard let self else { return }
            direction > 0 ? self.nextNote(nil) : self.previousNote(nil)
            // The incoming picture showed the note from the top; match it.
            self.scrollToTop()
        }

        searchBar.field.delegate = self
        searchBar.isHidden = true

        let column = NSStackView(views: [scrollView, searchBar])
        column.orientation = .vertical
        column.spacing = 0
        column.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: root.topAnchor),
            column.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            column.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.widthAnchor.constraint(equalTo: column.widthAnchor),
            searchBar.widthAnchor.constraint(equalTo: column.widthAnchor),
        ])

        // Position and pin, bottom-right, above the search bar when it's open.
        cornerInfo.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(cornerInfo)
        NSLayoutConstraint.activate([
            cornerInfo.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            cornerInfo.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -10),
        ])

        drawer.notes = { [weak self] in self?.notes ?? [] }
        drawer.currentID = { [weak self] in self?.current?.id }
        drawer.onOpen = { [weak self] note in self?.open(noteID: note.id) }
        drawer.trashCount = { [weak self] in (try? self?.store.trashedNotes().count) ?? 0 }
        drawer.onOpenTrash = { [weak self] in self?.onOpenTrash?() }
        drawer.onClose = { [weak self] in
            self?.scrim.isHidden = true
            self?.focusEditor()
        }
        scrim.isHidden = true
        scrim.onClick = { [weak self] in self?.drawer.close() }
        root.addSubview(scrim)
        root.addSubview(drawer)

        shortcuts.isHidden = true
        root.addSubview(shortcuts)
        watchCommandKey()

        view = root
        index = Int.max // no remembered note → open on the blank draft
        reload(keeping: Settings.lastNoteID)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        if !shortcuts.isHidden { shortcuts.layout(in: view.bounds) }
        if drawer.isOpen { layoutDrawer() }
    }

    /// Left side, full height; the scrim covers the rest.
    private func layoutDrawer() {
        let bounds = view.bounds
        let width = min(max(bounds.width * 0.62, 220), 320)
        drawer.frame = NSRect(x: 0, y: 0, width: width, height: bounds.height)
        scrim.frame = NSRect(x: width, y: 0, width: bounds.width - width, height: bounds.height)
    }

    // MARK: State

    /// Re-reads notes from the store, staying on `id` if it still exists.
    /// Skipped while an edit is unsaved, so the store's older text can't
    /// overwrite it.
    func reload(keeping id: Int64?) {
        guard save() else { return }
        notes = (try? store.activeNotes()) ?? []
        if let id, let i = notes.firstIndex(where: { $0.id == id }) {
            index = i
        } else {
            index = min(index, notes.count)
        }
        show()
    }

    /// Called after a sweep: picks up expired notes and updates countdowns.
    func refresh() {
        reload(keeping: current?.id)
    }

    func focusEditor() {
        view.window?.makeFirstResponder(textView)
    }

    private func show() {
        let body = current?.body ?? ""
        if textView.string != body {
            textView.string = body
            textView.setSelectedRange(NSRange(location: (body as NSString).length, length: 0))
            textView.undoManager?.removeAllActions()
        }
        updateStatus()
        Settings.lastNoteID = current?.id
    }

    private func updateStatus() {
        var state = CornerInfoView.State()
        state.keepOnTop = Settings.keepOnTop
        if let note = current {
            state.position = "\(index + 1)/\(notes.count)"
            state.pinned = note.pinned
        } else {
            state.position = "new"
            state.pinned = draftPinned
        }
        cornerInfo.state = state
        if !searchBar.isHidden {
            searchBar.matches = searchMatchIDs.isEmpty
                ? (searchBar.field.stringValue.isEmpty ? "" : "no matches")
                : "\(searchCursor + 1)/\(searchMatchIDs.count)"
        }
    }

    func textDidChange(_ notification: Notification) {
        save()
    }

    /// Writes the editor's text to the store. Returns false if that failed;
    /// the text stays in the editor and the next call tries again.
    @discardableResult
    private func save() -> Bool {
        let body = textView.string
        do {
            if var note = current {
                guard note.body != body else { return true }
                try store.updateBody(id: note.id, body: body)
                note.body = body
                note.updatedAt = Date()
                notes[index] = note
            } else {
                guard !body.isEmpty else { return true }
                var note = try store.insert(body: body)
                if draftPinned {
                    try? store.setPinned(id: note.id, true)
                    note.pinned = true
                    draftPinned = false
                }
                notes.append(note)
                index = notes.count - 1
                Settings.lastNoteID = note.id
            }
        } catch {
            if !hasUnsavedEdits { cornerInfo.flash("couldn't save  retrying") }
            hasUnsavedEdits = true
            return false
        }
        if hasUnsavedEdits { cornerInfo.flash("saved") }
        hasUnsavedEdits = false
        updateStatus()
        return true
    }

    /// Moves to another note. A blank note you leave behind is deleted outright.
    private func go(to target: Int) {
        var target = target
        guard target != index else { return }
        guard save() else { return NSSound.beep() }
        if let note = current, note.isBlank {
            try? store.purge(id: note.id)
            notes.remove(at: index)
            if target > index { target -= 1 }
        }
        draftPinned = false
        index = max(0, min(target, notes.count))
        show()
    }

    // MARK: Swiping between notes

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    private func swipeBegan() {
        swipeFired = false
        if !reduceMotion { swipe.begin() }
    }

    private func swipeChanged(_ travel: CGFloat) {
        if swipe.isActive {
            swipe.update(travel)
        } else if reduceMotion, !swipeFired, abs(travel) > 50 {
            // No motion: just switch, like turning a page.
            swipeFired = true
            travel < 0 ? nextNote(nil) : previousNote(nil)
        }
    }

    private func swipeEnded(_ velocity: CGFloat) {
        if swipe.isActive { swipe.end(velocity: velocity) }
    }

    /// Pictures of the current note and its neighbours, drawn by the real
    /// editor so they match it exactly. The editor's text, selection and
    /// scroll position are put back afterwards.
    private func renderForSwipe() -> (current: CGImage?, neighbours: SwipeTransition.Neighbours) {
        let current = snapshot(scrollView)
        let savedText = textView.string
        let savedSelection = textView.selectedRanges
        let savedOrigin = scrollView.contentView.bounds.origin

        func render(_ body: String) -> CGImage? {
            textView.string = body
            scrollToTop()
            return snapshot(scrollView)
        }
        var neighbours = SwipeTransition.Neighbours()
        if index > 0 { neighbours.previous = render(notes[index - 1].body) }
        // Past the newest note is a blank new note (its hint shows in the picture).
        if index < notes.count { neighbours.next = render(index + 1 < notes.count ? notes[index + 1].body : "") }

        textView.string = savedText
        textView.selectedRanges = savedSelection
        scrollView.contentView.scroll(to: savedOrigin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        return (current, neighbours)
    }

    private func snapshot(_ view: NSView) -> CGImage? {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.cgImage
    }

    private func scrollToTop() {
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: -scrollView.contentInsets.top))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    // MARK: Note actions

    @objc func previousNote(_ sender: Any?) {
        if index > 0 { go(to: index - 1) }
    }

    /// Past the newest note is the blank draft, i.e. a new note.
    @objc func nextNote(_ sender: Any?) {
        if index < notes.count { go(to: index + 1) }
    }

    @objc func newNote(_ sender: Any?) {
        go(to: notes.count)
        focusEditor()
    }

    @objc func jumpToNewest(_ sender: Any?) {
        if !notes.isEmpty { go(to: notes.count - 1) }
    }

    @objc func togglePin(_ sender: Any?) {
        guard var note = current else {
            draftPinned.toggle()
            updateStatus()
            cornerInfo.flash(draftPinned ? "\(Glyph.pin) pinned" : "unpinned")
            return
        }
        note.pinned.toggle()
        let now = Date()
        try? store.setPinned(id: note.id, note.pinned, now: now)
        if !note.pinned { note.updatedAt = now }
        notes[index] = note
        updateStatus()
        cornerInfo.flash(note.pinned ? "\(Glyph.pin) pinned" : "unpinned")
    }

    @objc func deleteNote(_ sender: Any?) {
        guard let note = current else { return }
        if note.isBlank {
            try? store.purge(id: note.id)
        } else {
            try? store.moveToTrash(id: note.id)
        }
        notes.remove(at: index)
        // Show the next newer note, or the previous one if this was the newest.
        index = notes.isEmpty ? 0 : min(index, notes.count - 1)
        show()
        if !note.isBlank { cornerInfo.flash("moved to trash  ⌘O to restore") }
    }

    // MARK: Appearance

    func applyAppearance(theme: Theme, paper: Paper, fontSize: CGFloat, translucent: Bool) {
        self.theme = theme
        backgroundView.color = translucent ? theme.background.withAlphaComponent(0.6) : theme.background
        textView.applyAppearance(theme: theme, paper: paper, fontSize: fontSize)
        cornerInfo.theme = theme
        searchBar.theme = theme
        drawer.theme = theme
        shortcuts.theme = theme
        updateStatus()
    }

    // MARK: Notes drawer

    @objc func toggleNotesDrawer(_ sender: Any?) {
        if drawer.isOpen {
            drawer.close()
            return
        }
        if !searchBar.isHidden { closeSearch() }
        layoutDrawer()
        scrim.isHidden = false
        drawer.open()
        // Slide in from the left.
        let final = drawer.frame
        drawer.frame.origin.x = -final.width
        scrim.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = Motion.easeOut
            drawer.animator().frame = final
            scrim.animator().alphaValue = 1
        }
    }

    /// Jumps to a note chosen in the drawer.
    private func open(noteID: Int64) {
        guard let target = notes.firstIndex(where: { $0.id == noteID }) else { return }
        go(to: target)
        focusEditor()
    }

    // MARK: Shortcut list (hold ⌘)

    /// Shows the shortcut list when ⌘ is held on its own for a moment.
    /// Any other key or modifier hides it; the key's shortcut still runs.
    private func watchCommandKey() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            self?.handleCommandKey(event)
            return event
        }
    }

    private func handleCommandKey(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .function])
        let onlyCommand = event.type == .flagsChanged && flags == .command
        guard onlyCommand, view.window?.isKeyWindow == true else { return hideShortcuts() }
        shortcutTimer?.invalidate()
        shortcutTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            self?.showShortcuts()
        }
    }

    private func showShortcuts() {
        shortcuts.layout(in: view.bounds)
        shortcuts.isHidden = false
    }

    private func hideShortcuts() {
        shortcutTimer?.invalidate()
        shortcutTimer = nil
        shortcuts.isHidden = true
    }

    // MARK: Window

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(toggleKeepOnTop(_:)):
            item.state = Settings.keepOnTop ? .on : .off
            return true
        case #selector(toggleReminder(_:)):
            item.state = Settings.reminderEnabled ? .on : .off
            return true
        case #selector(deleteNote(_:)):
            return current != nil
        default:
            return true
        }
    }

    /// The app applies this when it sees the setting change.
    @objc func toggleKeepOnTop(_ sender: Any?) {
        Settings.keepOnTop.toggle()
        updateStatus()
        cornerInfo.flash(Settings.keepOnTop ? "keeping on top" : "no longer on top")
    }

    /// Turns the pop-up timer on or off; the app restarts or stops it.
    @objc func toggleReminder(_ sender: Any?) {
        Settings.reminderEnabled.toggle()
        cornerInfo.flash(Settings.reminderEnabled ? "pop-up timer on" : "pop-up timer off")
    }

    // MARK: Search

    @objc func toggleSearch(_ sender: Any?) {
        if searchBar.isHidden {
            drawer.close()
            searchBar.isHidden = false
            view.window?.makeFirstResponder(searchBar.field)
            (searchBar.field.currentEditor() as? NSTextView)?.insertionPointColor = theme.accent
            updateStatus()
        } else {
            closeSearch()
        }
    }

    private func closeSearch() {
        searchBar.field.stringValue = ""
        searchBar.isHidden = true
        searchMatchIDs = []
        updateStatus()
        focusEditor()
    }

    func controlTextDidChange(_ obj: Notification) {
        let query = searchBar.field.stringValue
        // Newest matches first.
        searchMatchIDs = query.isEmpty ? [] : notes.reversed()
            .filter { $0.body.localizedCaseInsensitiveContains(query) }
            .map(\.id)
        searchCursor = 0
        showSearchMatch()
        updateStatus()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            // Enter cycles through matches.
            guard !searchMatchIDs.isEmpty else { return true }
            searchCursor = (searchCursor + 1) % searchMatchIDs.count
            showSearchMatch()
            updateStatus()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            closeSearch()
            return true
        default:
            return false
        }
    }

    private func showSearchMatch() {
        guard searchCursor < searchMatchIDs.count,
              let target = notes.firstIndex(where: { $0.id == searchMatchIDs[searchCursor] }) else { return }
        go(to: target)
        let range = (textView.string as NSString).range(of: searchBar.field.stringValue, options: .caseInsensitive)
        guard range.location != NSNotFound else { return }
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
        textView.showFindIndicator(for: range)
    }
}

/// Fills with a colour that follows light/dark mode (layer colours don't).
final class BackgroundView: NSView {
    var color: NSColor = .textBackgroundColor {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        dirtyRect.fill()
    }
}
