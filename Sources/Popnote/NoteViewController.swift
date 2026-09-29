import AppKit
import PopnoteCore

/// One note at a time: the editor, a vim-style status line, a "/" search
/// prompt and the ⌘K command palette. Everything is reachable by keyboard.
///
/// Notes are ordered oldest → newest. `index == notes.count` is the blank
/// draft past the newest note; it only becomes a real note once you type.
final class NoteViewController: NSViewController, NSTextViewDelegate, NSTextFieldDelegate, NSMenuItemValidation {
    var onHide: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    /// App-level commands (themes, The Void, settings…) for the palette.
    var appCommands: () -> [Command] = { [] }

    private let store: NoteStore
    private var notes: [Note] = []
    private var index = 0
    /// Pin pressed on the blank draft; applied when the note is created.
    private var draftPinned = false

    private let effectView = NSVisualEffectView()
    private let backgroundView = BackgroundView()
    private let scrollView = SwipeScrollView()
    private let textView = EditorTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
    private let searchBar = SearchBarView()
    private let statusBar = StatusBarView()
    private let palette = CommandPaletteView()
    private var theme = Theme.all[0]

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

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        // The transparent title bar sits over the top of the editor; start below it.
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 14, left: 0, bottom: 0, right: 0)
        scrollView.onSwipe = { [weak self] direction in
            guard let self else { return }
            direction > 0 ? self.nextNote(nil) : self.previousNote(nil)
        }

        searchBar.field.delegate = self
        searchBar.isHidden = true

        let column = NSStackView(views: [scrollView, searchBar, statusBar])
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
            statusBar.widthAnchor.constraint(equalTo: column.widthAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: StatusBarView.height),
        ])

        palette.commands = { [weak self] in self?.allCommands() ?? [] }
        palette.onClose = { [weak self] in self?.focusEditor() }
        root.addSubview(palette)

        view = root
        index = Int.max // no remembered note → open on the blank draft
        reload(keeping: Settings.lastNoteID)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        if palette.isOpen { palette.layout(in: view.bounds) }
    }

    // MARK: State

    /// Re-reads notes from the store, staying on `id` if it still exists.
    func reload(keeping id: Int64?) {
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
        var state = StatusBarView.State()
        state.mode = textView.mode
        state.keepOnTop = Settings.keepOnTop
        if let note = current {
            state.position = "\(index + 1)/\(notes.count)"
            state.pinned = note.isPinned
            state.pinnedByKeyword = note.isPinnedByKeyword && !note.pinned
            state.expiry = Expiry.remaining(for: note, now: Date(), ttl: Settings.noteTTL)
        } else {
            state.position = "new"
            state.pinned = draftPinned
        }
        if !searchBar.isHidden {
            state.right = searchMatchIDs.isEmpty
                ? (searchBar.field.stringValue.isEmpty ? "↩ next  esc close" : "no matches")
                : "\(searchCursor + 1)/\(searchMatchIDs.count)  ↩ next  esc close"
        }
        statusBar.state = state
    }

    func textDidChange(_ notification: Notification) {
        let body = textView.string
        if var note = current {
            guard note.body != body else { return }
            try? store.updateBody(id: note.id, body: body)
            note.body = body
            note.updatedAt = Date()
            notes[index] = note
        } else {
            guard !body.isEmpty, var note = try? store.insert(body: body) else { return }
            if draftPinned {
                try? store.setPinned(id: note.id, true)
                note.pinned = true
                draftPinned = false
            }
            notes.append(note)
            index = notes.count - 1
            Settings.lastNoteID = note.id
        }
        updateStatus()
    }

    /// Moves to another note. A blank note you leave behind is deleted outright.
    private func go(to target: Int) {
        var target = target
        guard target != index else { return }
        if let note = current, note.isBlank {
            try? store.purge(id: note.id)
            notes.remove(at: index)
            if target > index { target -= 1 }
        }
        draftPinned = false
        index = max(0, min(target, notes.count))
        show()
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
            statusBar.flash(draftPinned ? "\(Glyph.pin) pinned" : "unpinned")
            return
        }
        if note.isPinnedByKeyword && !note.pinned {
            statusBar.flash("pinned by \"\(Keywords.current.pin)\" on line 1")
            NSSound.beep()
            return
        }
        note.pinned.toggle()
        try? store.setPinned(id: note.id, note.pinned)
        notes[index] = note
        updateStatus()
        statusBar.flash(note.pinned ? "\(Glyph.pin) pinned" : "unpinned")
    }

    @objc func deleteNote(_ sender: Any?) {
        guard let note = current else { return }
        if note.isBlank {
            try? store.purge(id: note.id)
        } else {
            try? store.moveToVoid(id: note.id)
        }
        notes.remove(at: index)
        // Show the next newer note, or the previous one if this was the newest.
        index = notes.isEmpty ? 0 : min(index, notes.count - 1)
        show()
        if !note.isBlank { statusBar.flash("moved to the void  ⌘⇧⌫ to restore") }
    }

    // MARK: Appearance

    func applyAppearance(theme: Theme, paper: Paper, fontSize: CGFloat, translucent: Bool) {
        self.theme = theme
        backgroundView.color = translucent ? theme.background.withAlphaComponent(0.6) : theme.background
        textView.applyAppearance(theme: theme, paper: paper, fontSize: fontSize)
        statusBar.theme = theme
        searchBar.theme = theme
        palette.theme = theme
        updateStatus()
    }

    // MARK: Command palette

    @objc func toggleCommandPalette(_ sender: Any?) {
        if palette.isOpen {
            palette.close()
        } else {
            if !searchBar.isHidden { closeSearch() }
            palette.open()
        }
    }

    private func allCommands() -> [Command] {
        let editor = textView
        var commands = [
            Command("New note", "⌘N") { [weak self] in self?.newNote(nil) },
            Command("Previous note", "⌘[") { [weak self] in self?.previousNote(nil) },
            Command("Next note", "⌘]") { [weak self] in self?.nextNote(nil) },
            Command("Newest note", "⌘0") { [weak self] in self?.jumpToNewest(nil) },
            Command(current?.isPinned == true || (current == nil && draftPinned) ? "Unpin note" : "Pin note", "⌘P") {
                [weak self] in self?.togglePin(nil)
            },
            Command("Move note to the void", "⌘⌫") { [weak self] in self?.deleteNote(nil) },
            Command("Search notes", "⌘F") { [weak self] in self?.toggleSearch(nil) },
            Command("Cycle line type", "⌘⇧M") { editor.cycleLineType(nil) },
            Command("Check / uncheck item", "⌘↩") { editor.toggleCheckbox(nil) },
            Command(Settings.keepOnTop ? "Stop keeping on top" : "Keep on top", "⌘⇧T") { [weak self] in
                self?.toggleKeepOnTop(nil)
            },
        ]
        if current.map({ !$0.isBlank }) == true {
            commands += [
                Command("Copy note text", "⌘⇧C") { [weak self] in self?.copyNoteText(nil) },
                Command("Save as text…") { [weak self] in self?.saveAsText(nil) },
                Command("Save as markdown…") { [weak self] in self?.saveAsMarkdown(nil) },
                Command("Save as PDF…") { [weak self] in self?.saveAsPDF(nil) },
                Command("Send to Apple Notes") { [weak self] in self?.sendToAppleNotes(nil) },
                Command("Send to Obsidian") { [weak self] in self?.sendToObsidian(nil) },
                Command("Send to Bear") { [weak self] in self?.sendToBear(nil) },
            ]
        }
        return commands + appCommands()
    }

    // MARK: Export and window

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(toggleKeepOnTop(_:)):
            item.state = Settings.keepOnTop ? .on : .off
            return true
        case #selector(copyNoteText(_:)), #selector(saveAsText(_:)), #selector(saveAsMarkdown(_:)),
             #selector(saveAsPDF(_:)), #selector(sendToAppleNotes(_:)), #selector(sendToObsidian(_:)),
             #selector(sendToBear(_:)):
            return current.map { !$0.isBlank } ?? false
        case #selector(deleteNote(_:)):
            return current != nil
        default:
            return true
        }
    }

    @objc func copyNoteText(_ sender: Any?) {
        guard let note = current else { return }
        Export.copyText(note)
        statusBar.flash("copied to clipboard")
    }
    @objc func saveAsText(_ sender: Any?) { if let note = current { Export.save(note, as: .text, from: view.window) } }
    @objc func saveAsMarkdown(_ sender: Any?) { if let note = current { Export.save(note, as: .markdown, from: view.window) } }
    @objc func saveAsPDF(_ sender: Any?) { if let note = current { Export.save(note, as: .pdf, from: view.window) } }
    @objc func sendToAppleNotes(_ sender: Any?) { if let note = current { Export.sendToAppleNotes(note) } }
    @objc func sendToObsidian(_ sender: Any?) { if let note = current { Export.sendToObsidian(note) } }
    @objc func sendToBear(_ sender: Any?) { if let note = current { Export.sendToBear(note) } }

    /// The app applies this when it sees the setting change.
    @objc func toggleKeepOnTop(_ sender: Any?) {
        Settings.keepOnTop.toggle()
        updateStatus()
        statusBar.flash(Settings.keepOnTop ? "keeping on top" : "no longer on top")
    }

    @objc func openSettings(_ sender: Any?) { onOpenSettings?() }

    // MARK: Search

    @objc func toggleSearch(_ sender: Any?) {
        if searchBar.isHidden {
            palette.close()
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
