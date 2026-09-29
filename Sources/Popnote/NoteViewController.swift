import AppKit
import PopnoteCore

/// The note editor: one note at a time, header with position, expiry and pin.
///
/// Notes are ordered oldest → newest. `index == notes.count` is the blank
/// draft past the newest note; it only becomes a real note once you type.
final class NoteViewController: NSViewController, NSTextViewDelegate, NSSearchFieldDelegate, NSMenuItemValidation {
    var onHide: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    private let store: NoteStore
    private var notes: [Note] = []
    private var index = 0
    /// Pin pressed on the blank draft; applied when the note is created.
    private var draftPinned = false

    private let scrollView = SwipeScrollView()
    private let textView = EditorTextView(frame: NSRect(x: 0, y: 0, width: 380, height: 400))
    private let positionLabel = NSTextField(labelWithString: "")
    private let expiryLabel = NSTextField(labelWithString: "")
    private var pinButton: NSButton!
    private var deleteButton: NSButton!
    private var moreButton: NSButton!
    private let effectView = NSVisualEffectView()
    private let backgroundView = BackgroundView()
    private var theme = Theme.named("system")
    private let searchField = NSSearchField()
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
        root.frame = NSRect(x: 0, y: 0, width: 380, height: 440)
        root.material = .popover
        root.blendingMode = .behindWindow
        root.state = .active
        backgroundView.frame = root.bounds
        backgroundView.autoresizingMask = [.width, .height]
        root.addSubview(backgroundView)

        for label in [positionLabel, expiryLabel] {
            label.font = .systemFont(ofSize: 11)
        }
        pinButton = iconButton("pin", "Pin (⌘P)", #selector(togglePin(_:)))
        deleteButton = iconButton("trash", "Move to The Void (⌘⌫)", #selector(deleteNote(_:)))
        moreButton = iconButton("ellipsis.circle", "Export and more", #selector(showMoreMenu(_:)))

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let header = NSStackView(views: [positionLabel, spacer, expiryLabel, pinButton, deleteButton, moreButton])
        header.spacing = 8
        // Leave room for the traffic-light buttons in the transparent title bar.
        header.edgeInsets = NSEdgeInsets(top: 0, left: 78, bottom: 0, right: 12)

        searchField.placeholderString = "Search notes"
        searchField.delegate = self
        searchField.isHidden = true
        let searchRow = NSStackView(views: [searchField])
        searchRow.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 4, right: 12)
        searchRow.isHidden = true

        textView.configure()
        textView.delegate = self
        textView.onEscape = { [weak self] in self?.onHide?() }

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.onSwipe = { [weak self] direction in
            guard let self else { return }
            direction > 0 ? self.nextNote(nil) : self.previousNote(nil)
        }

        let column = NSStackView(views: [header, searchRow, scrollView])
        column.orientation = .vertical
        column.spacing = 0
        column.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: root.topAnchor),
            column.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            column.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 28),
            header.widthAnchor.constraint(equalTo: column.widthAnchor),
            searchRow.widthAnchor.constraint(equalTo: column.widthAnchor),
            scrollView.widthAnchor.constraint(equalTo: column.widthAnchor),
        ])
        view = root

        index = Int.max // no remembered note → open on the blank draft
        reload(keeping: Settings.lastNoteID)
    }

    private func iconButton(_ symbol: String, _ tip: String, _ action: Selector) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip)!,
                              target: self, action: action)
        button.isBordered = false
        button.toolTip = tip
        button.contentTintColor = .secondaryLabelColor
        return button
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
        updateHeader()
        Settings.lastNoteID = current?.id
    }

    private func updateHeader() {
        let pinned: Bool
        if let note = current {
            positionLabel.stringValue = "\(index + 1) of \(notes.count)"
            pinned = note.isPinned
            if note.isPinnedByKeyword && !note.pinned {
                expiryLabel.stringValue = "pinned by keyword"
            } else if pinned {
                expiryLabel.stringValue = "pinned"
            } else {
                expiryLabel.stringValue = Expiry.label(for: note, now: Date(), ttl: Settings.noteTTL) ?? ""
            }
        } else {
            positionLabel.stringValue = "New note"
            pinned = draftPinned
            expiryLabel.stringValue = pinned ? "pinned" : ""
        }
        pinButton.image = NSImage(systemSymbolName: pinned ? "pin.fill" : "pin", accessibilityDescription: "Pin")
        pinButton.contentTintColor = pinned ? theme.accent : theme.secondary
        deleteButton.isEnabled = current != nil
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
        updateHeader()
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

    // MARK: Actions (menu items and buttons)

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
            updateHeader()
            return
        }
        if note.isPinnedByKeyword && !note.pinned {
            // Pinned by its first line; unpinning means removing that line.
            NSSound.beep()
            return
        }
        note.pinned.toggle()
        try? store.setPinned(id: note.id, note.pinned)
        notes[index] = note
        updateHeader()
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
    }

    // MARK: Appearance

    func applyAppearance(theme: Theme, paper: Paper, fontSize: CGFloat, translucent: Bool) {
        self.theme = theme
        backgroundView.color = translucent ? theme.background.withAlphaComponent(0.55) : theme.background
        textView.applyAppearance(theme: theme, paper: paper, fontSize: fontSize)
        for label in [positionLabel, expiryLabel] { label.textColor = theme.secondary }
        for button in [deleteButton, moreButton] { button?.contentTintColor = theme.secondary }
        updateHeader()
    }

    // MARK: Export and more

    @objc private func showMoreMenu(_ sender: NSButton) {
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        add("Copy Note Text", #selector(copyNoteText(_:)))
        menu.addItem(.separator())
        add("Save as Text…", #selector(saveAsText(_:)))
        add("Save as Markdown…", #selector(saveAsMarkdown(_:)))
        add("Save as PDF…", #selector(saveAsPDF(_:)))
        menu.addItem(.separator())
        add("Send to Apple Notes", #selector(sendToAppleNotes(_:)))
        add("Send to Obsidian", #selector(sendToObsidian(_:)))
        add("Send to Bear", #selector(sendToBear(_:)))
        menu.addItem(.separator())
        add("Keep on Top", #selector(toggleKeepOnTop(_:)))
        add("Settings…", #selector(openSettings(_:)))
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

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

    @objc func copyNoteText(_ sender: Any?) { if let note = current { Export.copyText(note) } }
    @objc func saveAsText(_ sender: Any?) { if let note = current { Export.save(note, as: .text, from: view.window) } }
    @objc func saveAsMarkdown(_ sender: Any?) { if let note = current { Export.save(note, as: .markdown, from: view.window) } }
    @objc func saveAsPDF(_ sender: Any?) { if let note = current { Export.save(note, as: .pdf, from: view.window) } }
    @objc func sendToAppleNotes(_ sender: Any?) { if let note = current { Export.sendToAppleNotes(note) } }
    @objc func sendToObsidian(_ sender: Any?) { if let note = current { Export.sendToObsidian(note) } }
    @objc func sendToBear(_ sender: Any?) { if let note = current { Export.sendToBear(note) } }

    /// The app applies this when it sees the setting change.
    @objc func toggleKeepOnTop(_ sender: Any?) { Settings.keepOnTop.toggle() }
    @objc func openSettings(_ sender: Any?) { onOpenSettings?() }

    // MARK: Search

    @objc func toggleSearch(_ sender: Any?) {
        if searchField.isHidden {
            searchField.isHidden = false
            searchField.superview?.isHidden = false
            view.window?.makeFirstResponder(searchField)
        } else {
            closeSearch()
        }
    }

    private func closeSearch() {
        searchField.stringValue = ""
        searchField.isHidden = true
        searchField.superview?.isHidden = true
        searchMatchIDs = []
        focusEditor()
    }

    func controlTextDidChange(_ obj: Notification) {
        let query = searchField.stringValue
        // Newest matches first.
        searchMatchIDs = query.isEmpty ? [] : notes.reversed()
            .filter { $0.body.localizedCaseInsensitiveContains(query) }
            .map(\.id)
        searchCursor = 0
        showSearchMatch()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            // Enter cycles through matches.
            guard !searchMatchIDs.isEmpty else { return true }
            searchCursor = (searchCursor + 1) % searchMatchIDs.count
            showSearchMatch()
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
        let range = (textView.string as NSString).range(of: searchField.stringValue, options: .caseInsensitive)
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
