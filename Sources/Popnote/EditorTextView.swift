import AppKit
import PopnoteCore

/// The note editor. Plain text, with list markers kept in the text as
/// Markdown ("- [ ] ", "- ") but drawn as real checkboxes and bullets.
final class EditorTextView: NSTextView, NSTextStorageDelegate {
    var onEscape: (() -> Void)?

    private var mode = NoteMode.plain

    private enum DecorationKind { case checkbox(checked: Bool), bullet }
    /// A hidden marker with something drawn in its place.
    private struct Decoration {
        let range: NSRange
        let kind: DecorationKind
    }
    private var decorations: [Decoration] = []

    private(set) var theme = Theme.all[0]
    private var paper = Paper.blank
    private var bodyFont = Fonts.mono(14)
    /// Width of one character cell in the monospaced font.
    private var cell: CGFloat { (" " as NSString).size(withAttributes: [.font: bodyFont]).width }
    /// Set while we insert text ourselves, so it isn't mistaken for typing.
    private var isApplyingEdit = false

    func configure() {
        _ = layoutManager // opt into TextKit 1, which we use to find where markers are drawn
        textStorage?.delegate = self
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        drawsBackground = false
        font = bodyFont
        textContainerInset = NSSize(width: 14, height: 12)
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        textContainer?.widthTracksTextView = true
    }

    func applyAppearance(theme: Theme, paper: Paper, fontSize: CGFloat) {
        self.theme = theme
        self.paper = paper
        bodyFont = Fonts.mono(fontSize)
        insertionPointColor = theme.accent
        selectedTextAttributes = [.backgroundColor: theme.accent.withAlphaComponent(0.25)]
        guard let textStorage else { return }
        textStorage.beginEditing()
        restyle(textStorage)
        textStorage.endEditing()
        // Not in `restyle`: setting typing attributes reads the selection, which
        // is stale mid-edit (e.g. ⌘A then switching notes) and makes AppKit throw.
        typingAttributes = [.font: bodyFont, .foregroundColor: theme.text]
    }

    /// At least as tall as the visible area, so paper lines fill the panel
    /// and clicking below the text still focuses it.
    override func setFrameSize(_ newSize: NSSize) {
        var size = newSize
        // Exactly the visible height (excluding the scroll view's insets), so a
        // short note isn't scrollable and the scroll bar doesn't flash.
        if let scrollView = enclosingScrollView {
            let insets = scrollView.contentInsets
            size.height = max(size.height, scrollView.contentSize.height - insets.top - insets.bottom)
        }
        super.setFrameSize(size)
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    /// Called after ⌘C copied the whole note (nothing was selected).
    var onCopiedNote: (() -> Void)?

    /// ⌘C with nothing selected copies the whole note, minus its keyword line.
    override func copy(_ sender: Any?) {
        guard selectedRange().length == 0 else { return super.copy(sender) }
        let text = NoteText.content(of: Note(id: 0, body: string, createdAt: Date(), updatedAt: Date()))
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return NSSound.beep() }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        onCopiedNote?()
    }

    // MARK: Styling

    /// Restyles on every text change, before layout and before the selection
    /// moves, so markers are always hidden and `decorations` is never stale.
    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        restyle(textStorage)
    }

    private func restyle(_ storage: NSTextStorage) {
        let text = storage.string as NSString
        let full = NSRange(location: 0, length: text.length)
        let newMode = NoteMode(text: storage.string)
        if newMode != mode {
            mode = newMode
            // Not while the text storage is mid-edit: AppKit throws.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isContinuousSpellCheckingEnabled = self.mode != .code
            }
        }
        let base: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: theme.text,
        ]
        storage.setAttributes(base, range: full)

        // Dim the keyword line ("list", "code", "pin").
        if let keyword = Note.keyword(of: storage.string), Keywords.current.firstLine.contains(keyword) {
            storage.addAttribute(.foregroundColor, value: theme.dim,
                                 range: text.lineRange(for: NSRange(location: 0, length: 0)))
        }

        var found: [Decoration] = []
        if mode != .code {
            text.enumerateSubstrings(in: full, options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
                let parsed = Markers.parse(text.substring(with: lineRange))
                guard parsed.markerLength > 0 else { return }
                let marker = NSRange(location: lineRange.location + (parsed.indent as NSString).length,
                                     length: parsed.markerLength)
                let content = NSRange(location: NSMaxRange(marker), length: NSMaxRange(lineRange) - NSMaxRange(marker))
                switch parsed.kind {
                case .checkbox(let checked):
                    self.hideMarker(marker, in: storage, width: self.cell * CGFloat(Glyph.unchecked.count + 1))
                    found.append(Decoration(range: marker, kind: .checkbox(checked: checked)))
                    if checked {
                        storage.addAttributes([.foregroundColor: self.theme.dim,
                                               .strikethroughStyle: NSUnderlineStyle.single.rawValue], range: content)
                    }
                case .bullet:
                    self.hideMarker(marker, in: storage, width: self.cell * 2)
                    found.append(Decoration(range: marker, kind: .bullet))
                case .numbered:
                    storage.addAttribute(.foregroundColor, value: self.theme.accent, range: marker)
                case .plain:
                    break
                }
            }
        }
        decorations = found
        needsDisplay = true
    }

    /// Makes a marker invisible and squeezes it to a fixed width, so text lines
    /// up the same whether a box is checked ("[x]" is wider than "[ ]") or not.
    private func hideMarker(_ range: NSRange, in storage: NSTextStorage, width: CGFloat) {
        let natural = storage.attributedSubstring(from: range).size().width
        storage.addAttributes([.foregroundColor: NSColor.clear,
                               .kern: (width - natural) / CGFloat(range.length)], range: range)
    }

    override func draw(_ dirtyRect: NSRect) {
        drawPaper(dirtyRect)
        super.draw(dirtyRect)
        if string.isEmpty { drawEmptyHint() }
        for decoration in decorations {
            let rect = markerRect(decoration.range)
            guard rect.intersects(dirtyRect) else { continue }
            switch decoration.kind {
            case .checkbox(let checked):
                drawGlyph(checked ? Glyph.checked : Glyph.unchecked, color: checked ? theme.ok : theme.dim, in: rect)
            case .bullet:
                drawGlyph(Glyph.bullet, color: theme.accent, in: rect)
            }
        }
    }

    /// Shown in an empty note until you type: where to start, and that holding
    /// ⌘ lists the shortcuts (like Notion's "Press '/' for commands").
    private func drawEmptyHint() {
        let faint: [NSAttributedString.Key: Any] = [.font: bodyFont, .foregroundColor: theme.dim.withAlphaComponent(0.7)]
        let hint = NSMutableAttributedString(string: "start typing  ·  hold ", attributes: faint)
        hint.append(NSAttributedString(string: "⌘", attributes: [.font: Fonts.mono(bodyFont.pointSize, weight: .bold),
                                                                  .foregroundColor: theme.dim]))
        hint.append(NSAttributedString(string: " for shortcuts", attributes: faint))
        let padding = textContainer?.lineFragmentPadding ?? 0
        hint.draw(at: NSPoint(x: textContainerOrigin.x + padding, y: textContainerOrigin.y))
    }

    /// Lined paper has a rule under every line of text; grid adds columns.
    private func drawPaper(_ dirtyRect: NSRect) {
        guard paper != .blank, let layoutManager else { return }
        let step = layoutManager.defaultLineHeight(for: bodyFont)
        let top = textContainerOrigin.y
        theme.rule.setFill()
        var y = top + (max(0, ((dirtyRect.minY - top) / step).rounded(.down)) + 1) * step
        while y <= dirtyRect.maxY + step {
            NSRect(x: dirtyRect.minX, y: y.rounded() - 1, width: dirtyRect.width, height: 1).fill()
            y += step
        }
        guard paper == .grid else { return }
        var x = textContainerOrigin.x + (max(0, ((dirtyRect.minX - textContainerOrigin.x) / step).rounded(.down))) * step
        while x <= dirtyRect.maxX {
            NSRect(x: x.rounded(), y: dirtyRect.minY, width: 1, height: dirtyRect.height).fill()
            x += step
        }
    }

    private func markerRect(_ range: NSRange) -> NSRect {
        guard let layoutManager, let textContainer else { return .zero }
        let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        return layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
            .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
    }

    /// Icons are text in the note's own font. Nerd Font "Mono" icons are squeezed
    /// into one cell, so they're drawn a little larger, centred on the line.
    private func drawGlyph(_ glyph: String, color: NSColor, in rect: NSRect) {
        let scale: CGFloat = Fonts.hasNerdGlyphs ? 1.25 : 1
        let font = Fonts.mono(bodyFont.pointSize * scale)
        let string = NSAttributedString(string: glyph, attributes: [.font: font, .foregroundColor: color])
        let size = string.size()
        let lineHeight = layoutManager?.defaultLineHeight(for: bodyFont) ?? rect.height
        string.draw(at: NSPoint(x: rect.minX, y: rect.minY + (lineHeight - size.height) / 2))
    }

    // MARK: Caret

    /// Keeps the caret out of hidden markers: it jumps over them instead.
    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        var ranges = ranges
        if ranges.count == 1, let r = ranges.first?.rangeValue, r.length == 0,
           let hit = decorations.first(where: { r.location > $0.range.location && r.location < NSMaxRange($0.range) }) {
            let movingLeft = r.location < selectedRange().location
            let snapped = movingLeft ? hit.range.location : NSMaxRange(hit.range)
            ranges = [NSValue(range: NSRange(location: snapped, length: 0))]
        }
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
    }

    // MARK: Clicking checkboxes

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        for decoration in decorations {
            guard case .checkbox = decoration.kind,
                  markerRect(decoration.range).insetBy(dx: -2, dy: 0).contains(point) else { continue }
            toggleLine(at: decoration.range.location)
            return
        }
        super.mouseDown(with: event)
    }

    // MARK: Typing

    override func insertText(_ string: Any, replacementRange: NSRange) {
        super.insertText(string, replacementRange: replacementRange)
        guard mode != .code, !isApplyingEdit else { return }
        let typed = (string as? String) ?? (string as? NSAttributedString)?.string
        if typed == " " { expandCheckboxShortcut() }
    }

    /// "[] " at the start of a line becomes a checkbox.
    private func expandCheckboxShortcut() {
        let caret = selectedRange().location
        let line = lineRange(at: caret)
        let prefixRange = NSRange(location: line.location, length: caret - line.location)
        guard let expanded = Markers.expandShortcut((string as NSString).substring(with: prefixRange)) else { return }
        replace(prefixRange, with: expanded,
                select: NSRange(location: line.location + (expanded as NSString).length, length: 0))
    }

    /// Enter continues a list, or ends it on an empty item.
    override func insertNewline(_ sender: Any?) {
        guard mode != .code else { return super.insertNewline(sender) }
        let selection = selectedRange()
        let line = lineRange(at: selection.location)
        let lineText = (string as NSString).substring(with: line)
        switch Markers.newlineAction(for: lineText, caret: selection.location - line.location, inListNote: mode == .list) {
        case .plain:
            super.insertNewline(sender)
        case .continueWith(let prefix):
            isApplyingEdit = true
            insertText("\n" + prefix, replacementRange: selection)
            isApplyingEdit = false
        case .endList:
            replace(line, with: "", select: NSRange(location: line.location, length: 0))
        case .insertAbove(let prefix):
            // The caret stays at the start of the current item's text.
            let inserted = prefix + "\n"
            let parsed = Markers.parse(lineText)
            let contentStart = line.location + (inserted as NSString).length
                + (parsed.indent as NSString).length + parsed.markerLength
            replace(NSRange(location: line.location, length: 0), with: inserted,
                    select: NSRange(location: contentStart, length: 0))
        }
    }

    /// Backspace right after a hidden marker removes the whole marker.
    override func deleteBackward(_ sender: Any?) {
        let selection = selectedRange()
        if selection.length == 0, let hit = decorations.first(where: { NSMaxRange($0.range) == selection.location }) {
            replace(hit.range, with: "", select: NSRange(location: hit.range.location, length: 0))
            return
        }
        super.deleteBackward(sender)
    }

    /// Tab nests list items. Elsewhere it's a normal tab.
    override func insertTab(_ sender: Any?) {
        guard mode != .code, selectedLines().contains(where: { Markers.parse($0).markerLength > 0 }) else {
            return super.insertTab(sender)
        }
        transformSelectedLines(Markers.indented)
    }

    override func insertBacktab(_ sender: Any?) {
        transformSelectedLines(Markers.outdented)
    }

    override func paste(_ sender: Any?) {
        guard let raw = NSPasteboard.general.string(forType: .string) else { return super.paste(sender) }
        let selection = selectedRange()
        let cleaned: String
        if mode == .code {
            cleaned = raw.replacingOccurrences(of: "\r\n", with: "\n")
        } else {
            // Pasting into a list turns pasted lines into items of the same kind.
            let line = lineRange(at: selection.location)
            let lineText = (string as NSString).substring(with: line)
            var prefix = Markers.continuationPrefix(for: lineText)
            var prefixFirstLine = false
            if mode == .list && prefix == nil {
                prefix = Markers.marker(for: .checkbox(checked: false))
                prefixFirstLine = lineText.isEmpty && line.location > 0
            }
            cleaned = PasteCleaner.clean(raw, linePrefix: prefix, prefixFirstLine: prefixFirstLine,
                                         dropEmptyLines: mode == .list)
        }
        isApplyingEdit = true
        insertText(cleaned, replacementRange: selection)
        isApplyingEdit = false
    }

    // MARK: Commands (Format menu)

    /// ⌘↩: check or uncheck the item under the caret.
    @objc func toggleCheckbox(_ sender: Any?) {
        toggleLine(at: selectedRange().location)
    }

    /// Toggles the checkbox on the line containing `location`, then applies the
    /// "checked items" setting (keep, move to bottom, delete).
    func toggleLine(at location: Int) {
        let text = string as NSString
        var lines = string.components(separatedBy: "\n")
        let index = text.substring(to: location).components(separatedBy: "\n").count - 1
        guard index < lines.count, case .checkbox = Markers.parse(lines[index]).kind else {
            NSSound.beep()
            return
        }
        lines = Checklist.toggle(lines: lines, at: index, behavior: Settings.checkedBehavior).lines
        let newText = lines.joined(separator: "\n")
        let caret = min(selectedRange().location, (newText as NSString).length)
        let scrollOrigin = enclosingScrollView?.contentView.bounds.origin
        replace(NSRange(location: 0, length: text.length), with: newText, select: NSRange(location: caret, length: 0))
        if let scrollOrigin { scroll(scrollOrigin) }
    }

    // MARK: Helpers

    /// An undoable edit.
    private func replace(_ range: NSRange, with text: String, select selection: NSRange? = nil) {
        guard shouldChangeText(in: range, replacementString: text) else { return }
        isApplyingEdit = true
        textStorage?.replaceCharacters(in: range, with: text)
        isApplyingEdit = false
        didChangeText()
        if let selection { setSelectedRange(selection) }
    }

    /// The line containing `location`, without its newline.
    private func lineRange(at location: Int) -> NSRange {
        var start = 0, end = 0, contentsEnd = 0
        (string as NSString).getLineStart(&start, end: &end, contentsEnd: &contentsEnd,
                                          for: NSRange(location: location, length: 0))
        return NSRange(location: start, length: contentsEnd - start)
    }

    /// The lines touched by the selection, and their range (without the final newline).
    private func selectedBlock() -> (range: NSRange, lines: [String]) {
        let text = string as NSString
        let first = lineRange(at: selectedRange().location)
        let last = lineRange(at: NSMaxRange(selectedRange()))
        let range = NSRange(location: first.location, length: NSMaxRange(last) - first.location)
        return (range, text.substring(with: range).components(separatedBy: "\n"))
    }

    private func selectedLines() -> [String] { selectedBlock().lines }

    /// Applies `transform` to every selected line. With a single line the caret
    /// keeps its place in the text; with several, the whole block stays selected.
    private func transformSelectedLines(_ transform: (String) -> String) {
        let selection = selectedRange()
        let (range, lines) = selectedBlock()
        let newText = lines.map(transform).joined(separator: "\n")
        let newLength = (newText as NSString).length
        guard newText != (string as NSString).substring(with: range) else { return }
        let newSelection: NSRange
        if lines.count == 1 {
            let location = max(range.location, selection.location + newLength - range.length)
            newSelection = NSRange(location: location, length: selection.length)
        } else {
            newSelection = NSRange(location: range.location, length: newLength)
        }
        replace(range, with: newText, select: newSelection)
    }
}
