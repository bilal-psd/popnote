import AppKit
import PopnoteCore

/// ⌘O: a drawer listing every note, pinned first, then most recently edited,
/// with Trash at the bottom. Type to filter, ↑/↓ to move, ↩ to open, esc to close.
final class NotesDrawerView: NSView, NSTextFieldDelegate {
    var notes: () -> [Note] = { [] }
    var currentID: () -> Int64? = { nil }
    var onOpen: ((Note) -> Void)?
    var trashCount: () -> Int = { 0 }
    var onOpenTrash: (() -> Void)?
    var onClose: (() -> Void)?
    var theme = Theme.all[0] {
        didSet { applyTheme() }
    }

    private enum Row {
        case header(String)
        case note(Note)
        case trash(count: Int)

        var isSelectable: Bool {
            if case .header = self { return false }
            return true
        }
    }

    private let field = NSTextField()
    private let searchIcon = NSTextField(labelWithString: "")
    private var rows: [Row] = []
    private var selected = 0
    private var firstVisible = 0

    private let rowHeight: CGFloat = 24
    private let listTop: CGFloat = 46

    private(set) var isOpen = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        isHidden = true
        for view in [searchIcon, field] { addSubview(view) }
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = self
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    // MARK: Open / close

    func open() {
        field.stringValue = ""
        rebuild(selecting: currentID())
        isHidden = false
        isOpen = true
        window?.makeFirstResponder(field)
        (field.currentEditor() as? NSTextView)?.insertionPointColor = theme.accent
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        isHidden = true
        onClose?()
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        searchIcon.frame = NSRect(x: 14, y: 14, width: 18, height: 18)
        field.frame = NSRect(x: 34, y: 14, width: bounds.width - 46, height: 18)
        keepSelectionVisible()
    }

    // MARK: Rows

    private var noteRowIndices: [Int] {
        rows.indices.filter { rows[$0].isSelectable }
    }

    private var visibleCount: Int { max(1, Int((bounds.height - listTop - 6) / rowHeight)) }

    private func rebuild(selecting id: Int64? = nil) {
        let sections = Browse.sections(notes(), filter: field.stringValue)
        rows = []
        if !sections.pinned.isEmpty {
            rows.append(.header("PINNED"))
            rows += sections.pinned.map(Row.note)
        }
        if !sections.recent.isEmpty {
            rows.append(.header(sections.pinned.isEmpty ? "NOTES" : "RECENT"))
            rows += sections.recent.map(Row.note)
        }
        if field.stringValue.trimmingCharacters(in: .whitespaces).isEmpty {
            if !rows.isEmpty { rows.append(.header("")) }
            rows.append(.trash(count: trashCount()))
        }
        let noteRows = noteRowIndices
        selected = noteRows.first(where: { row in
            if case .note(let note) = rows[row] { return note.id == id } else { return false }
        }) ?? noteRows.first ?? 0
        firstVisible = 0
        keepSelectionVisible()
        needsDisplay = true
    }

    private func move(_ delta: Int) {
        let noteRows = noteRowIndices
        guard let position = noteRows.firstIndex(of: selected), !noteRows.isEmpty else { return }
        selected = noteRows[(position + delta + noteRows.count) % noteRows.count]
        keepSelectionVisible()
        needsDisplay = true
    }

    private func keepSelectionVisible() {
        // Show the section header above the first item too.
        let top = selected == noteRowIndices.first ? 0 : selected
        if top < firstVisible { firstVisible = top }
        if selected >= firstVisible + visibleCount { firstVisible = selected - visibleCount + 1 }
        firstVisible = max(0, min(firstVisible, max(0, rows.count - visibleCount)))
    }

    private func openSelected() {
        guard rows.indices.contains(selected) else { return NSSound.beep() }
        switch rows[selected] {
        case .note(let note):
            close()
            onOpen?(note)
        case .trash:
            close()
            onOpenTrash?()
        case .header:
            NSSound.beep()
        }
    }

    // MARK: Keys and mouse

    func controlTextDidChange(_ obj: Notification) {
        rebuild()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(moveDown(_:)), #selector(insertTab(_:)): move(1)
        case #selector(moveUp(_:)), #selector(insertBacktab(_:)): move(-1)
        case #selector(insertNewline(_:)): openSelected()
        case #selector(cancelOperation(_:)): close()
        default: return false
        }
        return true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard point.y > listTop else { return }
        let row = Int((point.y - listTop) / rowHeight) + firstVisible
        guard rows.indices.contains(row), rows[row].isSelectable else { return }
        selected = row
        openSelected()
    }

    override func scrollWheel(with event: NSEvent) {
        let step = event.scrollingDeltaY > 0 ? -1 : event.scrollingDeltaY < 0 ? 1 : 0
        firstVisible = max(0, min(firstVisible + step, max(0, rows.count - visibleCount)))
        needsDisplay = true
    }

    // MARK: Drawing

    private func applyTheme() {
        searchIcon.font = Fonts.mono(12)
        searchIcon.stringValue = Glyph.search
        searchIcon.textColor = theme.accent
        field.font = Fonts.mono(12)
        field.textColor = theme.text
        field.placeholderAttributedString = NSAttributedString(
            string: "filter notes", attributes: [.font: Fonts.mono(12), .foregroundColor: theme.dim])
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        theme.surface.setFill()
        bounds.fill()
        theme.rule.setFill()
        NSRect(x: bounds.maxX - 1, y: 0, width: 1, height: bounds.height).fill()
        NSRect(x: 0, y: listTop - 6, width: bounds.width - 1, height: 1).fill()

        let font = Fonts.mono(12)
        let small = Fonts.mono(10, weight: .bold)
        if rows.isEmpty {
            let empty = NSAttributedString(string: "no notes", attributes: [.font: font, .foregroundColor: theme.dim])
            empty.draw(at: NSPoint(x: 16, y: listTop + 4))
            return
        }
        let truncating = NSMutableParagraphStyle()
        truncating.lineBreakMode = .byTruncatingTail
        let now = Date()
        for (offset, index) in (firstVisible..<min(rows.count, firstVisible + visibleCount)).enumerated() {
            let rect = NSRect(x: 6, y: listTop + CGFloat(offset) * rowHeight, width: bounds.width - 13, height: rowHeight)
            switch rows[index] {
            case .header(let title):
                let header = NSAttributedString(string: title, attributes: [.font: small, .foregroundColor: theme.dim])
                header.draw(at: NSPoint(x: rect.minX + 8, y: rect.maxY - header.size().height - 3))
            case .trash(let count):
                if index == selected {
                    theme.accent.withAlphaComponent(0.18).setFill()
                    NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
                }
                let label = NSAttributedString(string: "  \(Glyph.trash) trash", attributes: [
                    .font: font, .foregroundColor: index == selected ? theme.accent : theme.dim,
                ])
                let meta = NSAttributedString(string: "\(count)", attributes: [.font: font, .foregroundColor: theme.dim])
                let y = rect.minY + (rowHeight - label.size().height) / 2
                label.draw(at: NSPoint(x: rect.minX + 4, y: y))
                meta.draw(at: NSPoint(x: rect.maxX - meta.size().width - 8, y: y))
            case .note(let note):
                let isSelected = index == selected
                if isSelected {
                    theme.accent.withAlphaComponent(0.18).setFill()
                    NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
                }
                let meta = NSAttributedString(
                    string: note.isPinned ? Glyph.pin : Browse.age(of: note, now: now),
                    attributes: [.font: font, .foregroundColor: note.isPinned ? theme.accent : theme.dim])
                let metaWidth = meta.size().width
                let isCurrent = note.id == currentID()
                let title = NoteText.title(of: note)
                let color = isSelected ? theme.accent : (isCurrent ? theme.text : theme.text.withAlphaComponent(0.85))
                let titleString = NSAttributedString(string: (isCurrent ? "● " : "  ") + title, attributes: [
                    .font: font, .foregroundColor: color, .paragraphStyle: truncating,
                ])
                let y = rect.minY + (rowHeight - meta.size().height) / 2
                titleString.draw(in: NSRect(x: rect.minX + 4, y: y, width: rect.width - metaWidth - 20, height: rowHeight))
                meta.draw(at: NSPoint(x: rect.maxX - metaWidth - 8, y: y))
            }
        }
    }
}

/// Dims the editor while the drawer is open; clicking it closes the drawer.
final class ScrimView: NSView {
    var onClick: (() -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.25).setFill()
        dirtyRect.fill()
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}
