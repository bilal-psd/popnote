import AppKit

/// The floating note window. Visible on every Space and over fullscreen apps.
final class NotePanel: NSPanel {
    init(contentViewController: NSViewController) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 380, height: 440),
                   styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                   backing: .buffered, defer: false)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        minSize = NSSize(width: 260, height: 200)
        backgroundColor = .textBackgroundColor
        self.contentViewController = contentViewController
        if !setFrameUsingName("PopnotePanel") { center() }
        setFrameAutosaveName("PopnotePanel")
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
