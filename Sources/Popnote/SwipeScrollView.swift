import AppKit

/// Scroll view that turns a horizontal two-finger swipe into note navigation.
/// Vertical scrolling and mouse wheels behave normally.
final class SwipeScrollView: NSScrollView {
    /// -1 = previous (older) note, +1 = next (newer) note.
    var onSwipe: ((Int) -> Void)?

    private enum Axis { case undecided, horizontal, vertical }
    private var axis = Axis.undecided
    private var travelled: CGFloat = 0
    private var fired = false
    private let threshold: CGFloat = 50

    override func scrollWheel(with event: NSEvent) {
        // Mouse wheels report no phases.
        if event.phase.isEmpty && event.momentumPhase.isEmpty {
            super.scrollWheel(with: event)
            return
        }
        if event.phase.contains(.mayBegin) || event.phase.contains(.began) {
            axis = .undecided
            travelled = 0
            fired = false
        }
        if axis == .undecided && !event.phase.isEmpty {
            let dx = abs(event.scrollingDeltaX), dy = abs(event.scrollingDeltaY)
            if dx > 0 || dy > 0 { axis = dx > dy ? .horizontal : .vertical }
        }
        guard axis == .horizontal else {
            super.scrollWheel(with: event)
            return
        }
        // Swallow the momentum that follows a horizontal swipe.
        guard !event.phase.isEmpty else { return }

        // Normalise to the direction the fingers moved, regardless of natural scrolling.
        let fingerDX = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
        travelled += fingerDX
        if !fired && abs(travelled) > threshold {
            fired = true
            // Fingers moving left reveals the next note, like turning a page.
            onSwipe?(travelled < 0 ? 1 : -1)
        }
    }
}
