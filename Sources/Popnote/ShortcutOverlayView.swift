import AppKit

/// Hold ⌘ briefly (0.3s) and this lists every shortcut. Pressing a key while
/// still holding ⌘ runs it as usual; letting go hides the list. It ignores
/// the mouse, so it never gets in the way.
final class ShortcutOverlayView: NSView {
    var theme = Theme.all[0] { didSet { needsDisplay = true } }

    private typealias Group = (title: String, items: [(key: String, label: String)])

    /// A 2×2 grid, grouped by what you're doing: moving around your notes,
    /// acting on this one, writing in it, and the window itself. Each row of
    /// the grid starts level, so the two columns line up. Settings sits apart,
    /// in the header.
    private let grid: [[Group]] = [
        [("notes", [("N", "new note"), ("[ ]", "previous / next"), ("O", "all notes")]),
         ("this note", [("P", "pin"), ("C", "copy"), ("⌫", "move to trash")])],
        [("writing", [("↩", "check / uncheck"), ("+ −", "text size")]),
         ("window", [("T", "keep on top"), ("R", "pop-up timer")])],
    ]
    private let settings = (key: ",", label: "settings")

    private let padding: CGFloat = 16
    /// The "hold ⌘ and press" line with Settings beside it (or below it, in
    /// one column), and the space below.
    private func header(twoColumns: Bool) -> CGFloat {
        (twoColumns ? keySize.height : keySize.height * 2 + 8) + 16
    }
    private let titleHeight: CGFloat = 20
    private let rowHeight: CGFloat = 28
    private let rowGap: CGFloat = 12
    private let columnWidth: CGFloat = 170
    private let columnGap: CGFloat = 12
    /// Every key is this size, whatever's on it.
    private let keySize = NSSize(width: 36, height: 22)
    private let keyGap: CGFloat = 10

    override var isFlipped: Bool { true }

    /// Clicks go straight through to the note.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Centred in `container`; one column if it's narrow.
    func layout(in container: NSRect) {
        let twoColumns = container.width >= 380
        let width = (twoColumns ? columnWidth * 2 + columnGap : columnWidth) + padding * 2
        let rows = twoColumns ? grid : grid.flatMap { $0 }.map { [$0] }
        let body = rows.map(rowHeight(of:)).reduce(0, +) + CGFloat(rows.count - 1) * rowGap
        let height = header(twoColumns: twoColumns) + body + padding * 2
        frame = NSRect(x: (container.midX - width / 2).rounded(), y: (container.midY - height / 2).rounded(),
                       width: width, height: height)
        needsDisplay = true
    }

    private func rowHeight(of groups: [Group]) -> CGFloat {
        titleHeight + CGFloat(groups.map(\.items.count).max() ?? 0) * rowHeight
    }

    override func draw(_ dirtyRect: NSRect) {
        let box = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        theme.surface.setFill()
        box.fill()
        theme.rule.setStroke()
        box.lineWidth = 1
        box.stroke()

        let label: [NSAttributedString.Key: Any] = [.font: Fonts.mono(12), .foregroundColor: theme.dim]
        let title: [NSAttributedString.Key: Any] = [.font: Fonts.mono(10, weight: .bold), .foregroundColor: theme.dim]
        let twoColumns = bounds.width > columnWidth + padding * 2
        let hint = NSMutableAttributedString(string: "hold ⌘ and press", attributes: label)
        hint.addAttributes([.font: Fonts.mono(12, weight: .bold), .foregroundColor: theme.text],
                           range: (hint.string as NSString).range(of: "⌘"))
        hint.draw(at: NSPoint(x: padding, y: padding + (keySize.height - hint.size().height) / 2))
        // Settings, in the accent colour: over the right column, or on its
        // own line below when there's only one.
        let settingsLabel = NSAttributedString(string: settings.label, attributes: [.font: Fonts.mono(12),
                                                                                    .foregroundColor: theme.text])
        let settingsOrigin = twoColumns
            ? NSPoint(x: padding + columnWidth + columnGap, y: padding)
            : NSPoint(x: padding, y: padding + keySize.height + 8)
        drawKey(settings.key, at: settingsOrigin, color: theme.accent)
        settingsLabel.draw(at: NSPoint(x: settingsOrigin.x + keySize.width + keyGap,
                                       y: settingsOrigin.y + (keySize.height - settingsLabel.size().height) / 2))
        let rows = twoColumns ? grid : grid.flatMap { $0 }.map { [$0] }
        var top = padding + header(twoColumns: twoColumns)
        for groups in rows {
            for (column, group) in groups.enumerated() {
                let x = padding + CGFloat(column) * (columnWidth + columnGap)
                NSAttributedString(string: group.title, attributes: title).draw(at: NSPoint(x: x, y: top))
                for (index, item) in group.items.enumerated() {
                    let y = top + titleHeight + CGFloat(index) * rowHeight
                    drawKey(item.key, at: NSPoint(x: x, y: y + (rowHeight - keySize.height) / 2), color: theme.rule)
                    let text = NSAttributedString(string: item.label, attributes: label)
                    text.draw(at: NSPoint(x: x + keySize.width + keyGap, y: y + (rowHeight - text.size().height) / 2))
                }
            }
            top += rowHeight(of: groups) + rowGap
        }
    }

    /// A flat key outlined in `color`, with its symbol centred in the box.
    private func drawKey(_ key: String, at origin: NSPoint, color: NSColor) {
        let box = NSRect(origin: origin, size: keySize)
        let path = NSBezierPath(roundedRect: box.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
        color.setStroke()
        path.lineWidth = 1
        path.stroke()

        // Centred on the ink, not the line box, so "," "↩" and "⌫" sit in the
        // middle just like the letters do.
        let font = Fonts.mono(11, weight: .bold)
        let symbol = color == theme.rule ? theme.text : color
        let text = NSAttributedString(string: key, attributes: [.font: font, .foregroundColor: symbol])
        let ink = CTLineGetImageBounds(CTLineCreateWithAttributedString(text), nil)
        text.draw(at: NSPoint(x: box.midX - ink.midX, y: box.midY + ink.midY - font.ascender))
    }
}
