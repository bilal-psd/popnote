import AppKit

/// Scroll view that turns a horizontal two-finger swipe into note navigation.
/// Vertical scrolling and mouse wheels behave normally.
///
/// It reports the whole gesture (start, finger travel, release with velocity)
/// so the note can follow the fingers. Distances are in the direction the
/// fingers moved, whatever the natural-scrolling setting: negative = left.
final class SwipeScrollView: NSScrollView {
    var onSwipeBegan: (() -> Void)?
    var onSwipeChanged: ((CGFloat) -> Void)?
    /// Called with the finger velocity at release, in points per second.
    var onSwipeEnded: ((CGFloat) -> Void)?

    private enum Axis { case undecided, horizontal, vertical }
    private var axis = Axis.undecided
    private var travelled: CGFloat = 0
    private var began = false

    /// Recent (time, distance) samples for the release velocity.
    private var samples: [(time: TimeInterval, travelled: CGFloat)] = []

    override func scrollWheel(with event: NSEvent) {
        // Mouse wheels report no phases.
        if event.phase.isEmpty && event.momentumPhase.isEmpty {
            super.scrollWheel(with: event)
            return
        }
        if event.phase.contains(.mayBegin) || event.phase.contains(.began) {
            axis = .undecided
            travelled = 0
            began = false
            samples = []
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

        if !began {
            began = true
            onSwipeBegan?()
        }
        let fingerDX = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
        travelled += fingerDX
        samples.append((event.timestamp, travelled))
        samples.removeAll { event.timestamp - $0.time > 0.08 }

        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            onSwipeEnded?(velocity())
            began = false
        } else {
            onSwipeChanged?(travelled)
        }
    }

    /// Finger speed over the last ~80ms, so a quick flick counts even if short.
    private func velocity() -> CGFloat {
        guard let first = samples.first, let last = samples.last, last.time > first.time else { return 0 }
        return (last.travelled - first.travelled) / CGFloat(last.time - first.time)
    }
}
