import AppKit

/// The floating note window. It can show over fullscreen apps, and on every
/// Space while kept on top (see `setFollowsAllSpaces`).
/// It keeps a (transparent) title bar for native resizing, rounded corners and
/// shadow, but hides the close/minimise/zoom buttons: Popnote is keyboard-driven.
final class NotePanel: NSPanel {
    init(contentViewController: NSViewController) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 400, height: 460),
                   styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                   backing: .buffered, defer: false)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        minSize = NSSize(width: 260, height: 200)
        backgroundColor = .textBackgroundColor
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
        self.contentViewController = contentViewController
        if !setFrameUsingName("PopnotePanel") { center() }
        setFrameAutosaveName("PopnotePanel")
    }

    /// On every Space while kept on top. Otherwise it stays on its Space and
    /// moves to the current one when opened, so switching Spaces hides it out
    /// of sight: an all-Spaces window got carried into the next Space while
    /// fading out, and flashed there.
    func setFollowsAllSpaces(_ follows: Bool) {
        // The two can't be set together: remove one before inserting the other.
        collectionBehavior.remove(follows ? .moveToActiveSpace : .canJoinAllSpaces)
        collectionBehavior.insert(follows ? .canJoinAllSpaces : .moveToActiveSpace)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
