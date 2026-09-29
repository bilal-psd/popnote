import AppKit
import PopnoteCore

/// A vim/tmux-style status line: mode chip, position, expiry on the left;
/// shortcut hints (or a brief message) on the right.
final class StatusBarView: NSView {
    struct State {
        var mode = NoteMode.plain
        var position = ""
        /// "2d 5h" until deletion, or nil when pinned.
        var expiry: String?
        var pinned = false
        var pinnedByKeyword = false
        var keepOnTop = false
        /// Replaces the hints, e.g. search results.
        var right: String?
    }

    var state = State() { didSet { needsDisplay = true } }
    var theme = Theme.all[0] { didSet { needsDisplay = true } }

    private var message: String?
    private var messageTimer: Timer?

    /// The most useful shortcuts, dropped from the end when space runs out.
    private let hints: [(key: String, label: String)] = [
        ("⌘K", "commands"), ("esc", "close"), ("⌘N", "new"), ("⌘[ ⌘]", "browse"), ("⌘P", "pin"), ("⌘⌫", "trash"),
    ]

    static let height: CGFloat = 24

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: Self.height) }
    override var mouseDownCanMoveWindow: Bool { true }

    /// Shows `text` in place of the hints for a moment.
    func flash(_ text: String) {
        message = text
        needsDisplay = true
        messageTimer?.invalidate()
        messageTimer = Timer.scheduledTimer(withTimeInterval: 1.8, repeats: false) { [weak self] _ in
            self?.message = nil
            self?.needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        theme.surface.setFill()
        bounds.fill()
        theme.rule.setFill()
        NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()

        let font = Fonts.mono(11)
        let bold = Fonts.mono(11, weight: .bold)
        func text(_ string: String, _ color: NSColor, _ f: NSFont? = nil) -> NSAttributedString {
            NSAttributedString(string: string, attributes: [.font: f ?? font, .foregroundColor: color])
        }

        // Mode chip.
        let (icon, name): (String, String) = {
            switch state.mode {
            case .plain: return (Glyph.note, "NOTE")
            case .list: return (Glyph.list, "LIST")
            case .code: return (Glyph.code, "CODE")
            }
        }()
        let chip = text(" \(icon) \(name) ", theme.background, bold)
        let chipWidth = ceil(chip.size().width)
        theme.accent.setFill()
        NSRect(x: 0, y: 0, width: chipWidth, height: bounds.height).fill()
        drawCentered(chip, x: 0)
        var x = chipWidth
        if let separator = Glyph.separatorRight {
            x += drawSeparator(separator, color: theme.accent, x: x)
        }

        // Position, expiry or pin, keep-on-top.
        let left = NSMutableAttributedString(attributedString: text(" \(state.position)", theme.text))
        if state.pinned {
            left.append(text("  \(Glyph.pin) \(state.pinnedByKeyword ? "pinned by keyword" : "pinned")", theme.accent))
        } else if let expiry = state.expiry {
            left.append(text("  \(Glyph.clock) \(expiry)", theme.dim))
        }
        if state.keepOnTop { left.append(text("  \(Glyph.top) on top", theme.dim)) }
        drawCentered(left, x: x)
        x += ceil(left.size().width)

        // Right side: a message, search results, or as many hints as fit.
        let available = bounds.width - x - 20
        let right: NSAttributedString
        if let message {
            right = text(message, theme.accent)
        } else if let override = state.right {
            right = text(override, theme.dim)
        } else {
            let hintLine = NSMutableAttributedString()
            for hint in hints {
                let piece = NSMutableAttributedString()
                if hintLine.length > 0 { piece.append(text("  ", theme.dim)) }
                piece.append(text(hint.key, theme.text.withAlphaComponent(0.75)))
                piece.append(text(" \(hint.label)", theme.dim))
                guard hintLine.size().width + piece.size().width <= available else { break }
                hintLine.append(piece)
            }
            right = hintLine
        }
        guard right.size().width <= available else { return }
        drawCentered(right, x: bounds.width - ceil(right.size().width) - 10)
    }

    private func drawCentered(_ string: NSAttributedString, x: CGFloat) {
        let height = string.size().height
        string.draw(at: NSPoint(x: x, y: ((bounds.height - height) / 2).rounded()))
    }

    /// Draws a powerline arrow sized to the full bar height. Returns its width.
    private func drawSeparator(_ glyph: String, color: NSColor, x: CGFloat) -> CGFloat {
        let probe = Fonts.mono(12)
        let size = 12 * bounds.height / (probe.ascender - probe.descender)
        let font = Fonts.mono(size)
        let string = NSAttributedString(string: glyph, attributes: [.font: font, .foregroundColor: color])
        string.draw(at: NSPoint(x: x, y: 0))
        return floor(string.size().width)
    }
}

/// vim-style "/" search prompt shown above the status line.
final class SearchBarView: NSView {
    let field = NSTextField()
    private let prompt = NSTextField(labelWithString: "/")

    var theme = Theme.all[0] {
        didSet { applyTheme() }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        for view in [prompt, field] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.placeholderString = "search notes"
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: StatusBarView.height),
            prompt.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            prompt.centerYAnchor.constraint(equalTo: centerYAnchor),
            field.leadingAnchor.constraint(equalTo: prompt.trailingAnchor, constant: 4),
            field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            field.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func applyTheme() {
        prompt.font = Fonts.mono(12, weight: .bold)
        prompt.textColor = theme.accent
        field.font = Fonts.mono(12)
        field.textColor = theme.text
        field.placeholderAttributedString = NSAttributedString(
            string: "search notes", attributes: [.font: Fonts.mono(12), .foregroundColor: theme.dim])
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        theme.surface.setFill()
        bounds.fill()
        theme.rule.setFill()
        NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
    }
}
