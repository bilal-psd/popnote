import AppKit
import PopnoteCore

struct Command {
    let title: String
    let shortcut: String
    let action: () -> Void

    init(_ title: String, _ shortcut: String = "", action: @escaping () -> Void) {
        self.title = title
        self.shortcut = shortcut
        self.action = action
    }
}

/// ⌘K: fuzzy-search every command. ↑/↓ (⌃P/⌃N and Tab work too, via the
/// standard key bindings) to move, ↩ to run, esc to close.
final class CommandPaletteView: NSView, NSTextFieldDelegate {
    var commands: () -> [Command] = { [] }
    var onClose: (() -> Void)?
    var theme = Theme.all[0] {
        didSet { applyTheme() }
    }

    private let field = NSTextField()
    private let prompt = NSTextField(labelWithString: "›")
    private var results: [Command] = []
    private var all: [Command] = []
    private var selected = 0

    private let rowHeight: CGFloat = 24
    private let fieldHeight: CGFloat = 36
    private let maxRows = 9

    var isOpen: Bool { !isHidden }

    override init(frame: NSRect) {
        super.init(frame: frame)
        isHidden = true
        for view in [prompt, field] { addSubview(view) }
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
        all = commands()
        field.stringValue = ""
        filter()
        isHidden = false
        window?.makeFirstResponder(field)
        (field.currentEditor() as? NSTextView)?.insertionPointColor = theme.accent
    }

    func close() {
        guard isOpen else { return }
        isHidden = true
        onClose?()
    }

    /// Sized to its results, pinned to the top of `container`.
    func layout(in container: NSRect) {
        let width = min(container.width - 24, 440)
        let rows = min(results.count, maxRows)
        let height = fieldHeight + CGFloat(rows) * rowHeight + (rows > 0 ? 8 : 0)
        frame = NSRect(x: container.midX - width / 2, y: container.maxY - height - 12, width: width, height: height)
        prompt.frame = NSRect(x: 12, y: 9, width: 14, height: 18)
        field.frame = NSRect(x: 28, y: 9, width: width - 40, height: 18)
        needsDisplay = true
    }

    private func relayout() {
        if let superview { layout(in: superview.bounds) }
    }

    // MARK: Filtering and keys

    private func filter() {
        results = Fuzzy.filter(all, query: field.stringValue, text: \.title)
        selected = 0
        relayout()
    }

    func controlTextDidChange(_ obj: Notification) {
        filter()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(moveDown(_:)), #selector(insertTab(_:)):
            move(1)
        case #selector(moveUp(_:)), #selector(insertBacktab(_:)):
            move(-1)
        case #selector(insertNewline(_:)):
            run(selected)
        case #selector(cancelOperation(_:)):
            close()
        default:
            return false
        }
        return true
    }

    private func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selected = (selected + delta + results.count) % results.count
        needsDisplay = true
    }

    private func run(_ index: Int) {
        guard results.indices.contains(index) else { return NSSound.beep() }
        let command = results[index]
        close()
        command.action()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let row = Int((point.y - fieldHeight) / rowHeight) + firstVisible
        if point.y > fieldHeight { run(row) }
    }

    // MARK: Drawing

    private var firstVisible: Int { max(0, selected - maxRows + 1) }

    private func applyTheme() {
        prompt.font = Fonts.mono(14, weight: .bold)
        prompt.textColor = theme.accent
        field.font = Fonts.mono(13)
        field.textColor = theme.text
        field.placeholderAttributedString = NSAttributedString(
            string: "type a command", attributes: [.font: Fonts.mono(13), .foregroundColor: theme.dim])
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let box = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        theme.surface.setFill()
        box.fill()
        theme.rule.setStroke()
        box.lineWidth = 1
        box.stroke()
        guard !results.isEmpty else { return }
        theme.rule.setFill()
        NSRect(x: 0, y: fieldHeight - 1, width: bounds.width, height: 1).fill()

        let font = Fonts.mono(12)
        for (row, index) in (firstVisible..<min(results.count, firstVisible + maxRows)).enumerated() {
            let command = results[index]
            let rect = NSRect(x: 4, y: fieldHeight + 4 + CGFloat(row) * rowHeight, width: bounds.width - 8, height: rowHeight)
            let isSelected = index == selected
            if isSelected {
                theme.accent.withAlphaComponent(0.18).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
            }
            let title = NSAttributedString(string: (isSelected ? "▸ " : "  ") + command.title, attributes: [
                .font: font, .foregroundColor: isSelected ? theme.accent : theme.text,
            ])
            let shortcut = NSAttributedString(string: command.shortcut, attributes: [.font: font, .foregroundColor: theme.dim])
            let y = rect.minY + (rowHeight - title.size().height) / 2
            title.draw(at: NSPoint(x: rect.minX + 6, y: y))
            shortcut.draw(at: NSPoint(x: rect.maxX - shortcut.size().width - 8, y: y))
        }
    }
}
