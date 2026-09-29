import AppKit

/// Hold ⌘ briefly (0.3s) and this lists every shortcut. Pressing a key while
/// still holding ⌘ runs it as usual; letting go hides the list. It ignores
/// the mouse, so it never gets in the way.
final class ShortcutOverlayView: NSView {
    var theme = Theme.all[0] { didSet { needsDisplay = true } }

    private let columns: [(title: String, items: [(key: String, label: String)])] = [
        ("notes", [
            ("N", "new note"), ("O", "all notes, trash"), ("[ ]", "previous / next"), ("0", "newest"),
            ("P", "pin"), ("⌫", "move to trash"), ("F", "search"),
        ]),
        ("editing", [
            ("C", "copy note"), ("↩", "check / uncheck"), ("= −", "text size"),
            ("T", "keep on top"), ("R", "pop-up timer"), (",", "settings"), ("W", "close"), ("Q", "quit"),
        ]),
    ]

    private let padding: CGFloat = 16
    private let rowHeight: CGFloat = 20
    private let keyWidth: CGFloat = 34

    override var isFlipped: Bool { true }

    /// Clicks go straight through to the note.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Centred in `container`; one column if it's narrow.
    func layout(in container: NSRect) {
        let twoColumns = container.width >= 380
        let columnWidth: CGFloat = 170
        let width = (twoColumns ? columnWidth * 2 + 12 : columnWidth) + padding * 2
        let rows = twoColumns
            ? (columns.map(\.items.count).max() ?? 0) + 1
            : columns.reduce(0) { $0 + $1.items.count + 1 } + 1
        let height = CGFloat(rows) * rowHeight + padding * 2 + 22
        frame = NSRect(x: (container.midX - width / 2).rounded(), y: (container.midY - height / 2).rounded(),
                       width: width, height: height)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let box = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        theme.surface.setFill()
        box.fill()
        theme.rule.setStroke()
        box.lineWidth = 1
        box.stroke()

        let font = Fonts.mono(12)
        let bold = Fonts.mono(12, weight: .bold)
        let small = Fonts.mono(10, weight: .bold)
        NSAttributedString(string: "⌘ +", attributes: [.font: bold, .foregroundColor: theme.text])
            .draw(at: NSPoint(x: padding, y: padding - 2))

        let twoColumns = bounds.width > 250
        var x = padding
        var y = padding + 22
        for column in columns {
            NSAttributedString(string: column.title.uppercased(), attributes: [.font: small, .foregroundColor: theme.dim])
                .draw(at: NSPoint(x: x, y: y + 4))
            y += rowHeight
            for item in column.items {
                NSAttributedString(string: item.key, attributes: [.font: bold, .foregroundColor: theme.text])
                    .draw(at: NSPoint(x: x, y: y + 2))
                NSAttributedString(string: item.label, attributes: [.font: font, .foregroundColor: theme.dim])
                    .draw(at: NSPoint(x: x + keyWidth, y: y + 2))
                y += rowHeight
            }
            if twoColumns {
                x += 170 + 12
                y = padding + 22
            }
        }
    }
}
