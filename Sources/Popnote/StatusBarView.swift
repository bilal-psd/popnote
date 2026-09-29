import AppKit
import PopnoteCore

/// A vim/tmux-style status line: notes-drawer button, position, expiry on the
/// left; shortcut hints (or a brief message) on the right.
final class StatusBarView: NSView {
    struct State {
        var position = ""
        /// "2d 5h" until deletion, or nil when pinned.
        var expiry: String?
        var pinned = false
        var pinnedByKeyword = false
        var keepOnTop = false
        /// Replaces the hints, e.g. search results.
        var right: String?
    }

    /// Height and type sizes. `current` is read when views are laid out.
    struct Size {
        var height: CGFloat
        var font: CGFloat
        var icon: CGFloat
        var iconWidth: CGFloat

        static let compact = Size(height: 21, font: 10, icon: 12, iconWidth: 26)
        static var current = compact
    }

    struct Colors {
        var background, text, dim, key, highlight, icon, divider, border: NSColor
    }

    /// No accent colour: the status line stays quiet, in the theme's text colours.
    func colors() -> Colors {
        Colors(background: theme.surface, text: theme.text, dim: theme.dim,
               key: theme.text.withAlphaComponent(0.75), highlight: theme.accent,
               icon: theme.text, divider: theme.rule, border: theme.rule)
    }

    var state = State() { didSet { needsDisplay = true } }
    var theme = Theme.all[0] {
        didSet {
            needsDisplay = true
            drawerButton.needsDisplay = true
        }
    }
    /// Clicked to open the notes drawer.
    let drawerButton = DrawerButton()

    private var message: String?
    private var messageTimer: Timer?

    /// The most useful shortcuts, dropped from the end when space runs out.
    private let hints: [(key: String, label: String)] = [
        ("⌘", "shortcuts"), ("esc", "close"), ("⌘N", "new"), ("⌘P", "pin"), ("⌘⌫", "trash"),
    ]

    static var height: CGFloat { Size.current.height }

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: Self.height) }
    override var mouseDownCanMoveWindow: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        drawerButton.bar = self
        addSubview(drawerButton)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        drawerButton.frame = NSRect(x: 0, y: 0, width: Size.current.iconWidth, height: bounds.height)
    }

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
        let c = colors()
        c.background.setFill()
        bounds.fill()
        c.border.setFill()
        NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()

        let font = Fonts.mono(Size.current.font)
        func text(_ string: String, _ color: NSColor, _ f: NSFont? = nil) -> NSAttributedString {
            NSAttributedString(string: string, attributes: [.font: f ?? font, .foregroundColor: color])
        }

        // The drawer button draws itself; text starts after it.
        var x = Size.current.iconWidth + 4

        // Position, expiry or pin, keep-on-top.
        let left = NSMutableAttributedString(attributedString: text(" \(state.position)", c.text))
        if state.pinned {
            left.append(text("  \(Glyph.pin) \(state.pinnedByKeyword ? "pinned by keyword" : "pinned")", c.highlight))
        } else if let expiry = state.expiry {
            left.append(text("  \(Glyph.clock) \(expiry)", c.dim))
        }
        if state.keepOnTop { left.append(text("  \(Glyph.top) on top", c.dim)) }
        drawCentered(left, x: x)
        x += ceil(left.size().width)

        // Right side: a message, search results, or as many hints as fit.
        let available = bounds.width - x - 20
        let right: NSAttributedString
        if let message {
            right = text(message, c.highlight)
        } else if let override = state.right {
            right = text(override, c.dim)
        } else {
            let hintLine = NSMutableAttributedString()
            for hint in hints {
                let piece = NSMutableAttributedString()
                if hintLine.length > 0 { piece.append(text("  ", c.dim)) }
                piece.append(text(hint.key, c.key))
                piece.append(text(" \(hint.label)", c.dim))
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
}

/// The icon at the left of the status line. Opens the notes drawer (same as ⌘O).
final class DrawerButton: NSView {
    var onClick: (() -> Void)?
    weak var bar: StatusBarView?
    private var hovering = false {
        didSet { needsDisplay = true }
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame: NSRect) {
        super.init(frame: frame)
        toolTip = "All notes (⌘O)"
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard let c = bar?.colors() else { return }
        if hovering {
            c.text.withAlphaComponent(0.08).setFill()
            bounds.fill()
        }
        let icon = NSAttributedString(string: Glyph.notes, attributes: [.font: Fonts.mono(StatusBarView.Size.current.icon), .foregroundColor: c.icon])
        let size = icon.size()
        icon.draw(at: NSPoint(x: ((bounds.width - size.width) / 2).rounded(), y: ((bounds.height - size.height) / 2).rounded()))
        c.divider.setFill()
        let inset = (bounds.height * 0.22).rounded()
        NSRect(x: bounds.maxX - 1, y: inset, width: 1, height: bounds.height - inset * 2).fill()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
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
        prompt.font = Fonts.mono(StatusBarView.Size.current.font + 1, weight: .bold)
        prompt.textColor = theme.accent
        let size = StatusBarView.Size.current.font + 1
        field.font = Fonts.mono(size)
        field.textColor = theme.text
        field.placeholderAttributedString = NSAttributedString(
            string: "search notes", attributes: [.font: Fonts.mono(size), .foregroundColor: theme.dim])
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        theme.surface.setFill()
        bounds.fill()
        theme.rule.setFill()
        NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
    }
}
