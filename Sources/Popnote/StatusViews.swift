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
