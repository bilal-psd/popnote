import AppKit

/// Muted text in the bottom-right corner: the note's position ("2/5" or
/// "new"), a pin if it's pinned, and brief messages like "copied note".
/// It ignores the mouse, so text underneath stays clickable.
final class CornerInfoView: NSView {
    struct State: Equatable {
        var position = ""
        var pinned = false
        var keepOnTop = false
    }

    var state = State() { didSet { refresh() } }
    var theme = Theme.all[0] { didSet { refresh() } }

    private var message: String?
    private var messageTimer: Timer?

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Shows `text` in place of the position for a moment.
    func flash(_ text: String) {
        message = text
        refresh()
        messageTimer?.invalidate()
        messageTimer = Timer.scheduledTimer(withTimeInterval: 1.8, repeats: false) { [weak self] _ in
            self?.message = nil
            self?.refresh()
        }
    }

    private var content: NSAttributedString {
        let font = Fonts.mono(10)
        let color = theme.dim
        func text(_ s: String) -> NSAttributedString {
            NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
        }
        if let message { return text(message) }
        var parts: [String] = []
        if state.keepOnTop { parts.append(Glyph.top) }
        if state.pinned { parts.append(Glyph.pin) }
        parts.append(state.position)
        return text(parts.joined(separator: "  "))
    }

    override var intrinsicContentSize: NSSize {
        let size = content.size()
        return NSSize(width: ceil(size.width), height: ceil(size.height))
    }

    private func refresh() {
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        content.draw(at: .zero)
    }
}

/// vim-style "/" search prompt shown at the bottom while searching, with
/// the match count on the right.
final class SearchBarView: NSView {
    static let height: CGFloat = 21

    let field = NSTextField()
    private let prompt = NSTextField(labelWithString: "/")
    private let count = NSTextField(labelWithString: "")

    var theme = Theme.all[0] {
        didSet { applyTheme() }
    }

    /// "2/5", "no matches", or "" before anything is typed.
    var matches: String {
        get { count.stringValue }
        set { count.stringValue = newValue }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        for view in [prompt, field, count] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        count.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.height),
            prompt.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            prompt.centerYAnchor.constraint(equalTo: centerYAnchor),
            field.leadingAnchor.constraint(equalTo: prompt.trailingAnchor, constant: 4),
            field.trailingAnchor.constraint(equalTo: count.leadingAnchor, constant: -8),
            field.centerYAnchor.constraint(equalTo: centerYAnchor),
            count.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            count.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func applyTheme() {
        prompt.font = Fonts.mono(11, weight: .bold)
        prompt.textColor = theme.accent
        field.font = Fonts.mono(11)
        field.textColor = theme.text
        field.placeholderAttributedString = NSAttributedString(
            string: "search notes   ↩ next   esc close", attributes: [.font: Fonts.mono(11), .foregroundColor: theme.dim])
        count.font = Fonts.mono(10)
        count.textColor = theme.dim
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        theme.surface.setFill()
        bounds.fill()
        theme.rule.setFill()
        NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
    }
}
