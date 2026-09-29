import AppKit

/// Makes the note follow your fingers during a two-finger swipe, with the
/// neighbouring note sliding in beside it, then springs into place on release.
///
/// It works on pictures: at the start of the gesture it snapshots the current
/// note and renders its neighbours, hides the real editor, and moves the
/// pictures. When the spring settles, the real editor switches notes (or
/// doesn't) and comes back.
final class SwipeTransition {
    struct Neighbours {
        var previous: CGImage?
        var next: CGImage?
    }

    /// The editor area to cover.
    private let target: NSView
    /// Renders the current note and its neighbours; called once per gesture.
    var render: () -> (current: CGImage?, neighbours: Neighbours) = { (nil, Neighbours()) }
    /// Switch notes: +1 = next, -1 = previous.
    var commit: (Int) -> Void = { _ in }

    private var stage: NSView?
    private var currentLayer: CALayer?
    private var incomingLayer: CALayer?
    private var neighbours = Neighbours()
    /// +1 when the fingers move left (next note comes in from the right), -1 otherwise.
    private var direction = 0
    private var offset: CGFloat = 0
    private(set) var isSettling = false

    /// Space between the two notes while they're side by side.
    private let gap: CGFloat = 24

    init(target: NSView) {
        self.target = target
    }

    var isActive: Bool { stage != nil }

    // MARK: Gesture

    func begin() {
        guard !isActive, let host = target.superview?.superview ?? target.superview else { return }
        let rendered = render()
        guard let current = rendered.current else { return }
        neighbours = rendered.neighbours

        let stage = NSView(frame: host.convert(target.bounds, from: target))
        stage.wantsLayer = true
        stage.layer?.masksToBounds = true
        let layer = makeLayer(current, in: stage)
        stage.layer?.addSublayer(layer)
        // Just above the editor's column, below the corner info, drawer and overlays.
        host.addSubview(stage, positioned: .above, relativeTo: target.superview)
        target.alphaValue = 0

        self.stage = stage
        currentLayer = layer
        direction = 0
        offset = 0
    }

    /// `travel` is the total finger distance so far (negative = left).
    func update(_ travel: CGFloat) {
        guard !isSettling, let stage, let currentLayer else { return }
        let newDirection = travel < 0 ? 1 : -1
        if newDirection != direction {
            direction = newDirection
            incomingLayer?.removeFromSuperlayer()
            incomingLayer = (direction == 1 ? neighbours.next : neighbours.previous).map { makeLayer($0, in: stage) }
            if let incomingLayer { stage.layer?.addSublayer(incomingLayer) }
        }
        // Past the first/last note there's nothing to reveal: resist instead.
        offset = incomingLayer == nil ? rubberBand(travel, width: stage.bounds.width) : travel
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        position(currentLayer, incomingLayer, width: stage.bounds.width)
        CATransaction.commit()
    }

    /// Commits if dragged past 30% of the width or flicked, otherwise springs back.
    func end(velocity: CGFloat) {
        guard !isSettling, let stage, let currentLayer else { return }
        let width = stage.bounds.width
        let flicked = abs(velocity) > 250 && (velocity < 0) == (offset < 0) && abs(offset) > 12
        let commits = incomingLayer != nil && (abs(offset) > width * 0.3 || flicked)
        let finalOffset = commits ? -CGFloat(direction) * (width + gap) : 0

        isSettling = true
        let committedDirection = direction
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self else { return }
            if commits { self.commit(committedDirection) }
            self.finish()
        }
        spring(currentLayer, to: width / 2 + finalOffset, velocity: velocity)
        if let incomingLayer {
            spring(incomingLayer, to: width / 2 + finalOffset + CGFloat(direction) * (width + gap), velocity: velocity)
        }
        CATransaction.commit()
        offset = finalOffset
    }

    // MARK: Helpers

    private func finish() {
        target.alphaValue = 1
        stage?.removeFromSuperview()
        stage = nil
        currentLayer = nil
        incomingLayer = nil
        isSettling = false
    }

    private func makeLayer(_ image: CGImage, in stage: NSView) -> CALayer {
        let layer = CALayer()
        layer.contents = image
        layer.contentsScale = stage.window?.backingScaleFactor ?? 2
        layer.frame = stage.bounds
        return layer
    }

    private func position(_ current: CALayer, _ incoming: CALayer?, width: CGFloat) {
        current.position.x = width / 2 + offset
        incoming?.position.x = width / 2 + offset + CGFloat(direction) * (width + gap)
    }

    /// The further you pull, the less it moves (the iOS scroll-view formula).
    private func rubberBand(_ travel: CGFloat, width: CGFloat) -> CGFloat {
        let resistance: CGFloat = 0.55
        let magnitude = (1 - 1 / (abs(travel) * resistance / width + 1)) * width
        return travel < 0 ? -magnitude : magnitude
    }

    /// A critically-damped-ish spring (no visible bounce) that starts at the
    /// finger's release speed, so a flick carries straight through.
    private func spring(_ layer: CALayer, to x: CGFloat, velocity: CGFloat) {
        let from = layer.presentation()?.position.x ?? layer.position.x
        let animation = CASpringAnimation(keyPath: "position.x")
        animation.fromValue = from
        animation.toValue = x
        animation.mass = 1
        animation.stiffness = 320
        animation.damping = 34
        let distance = x - from
        animation.initialVelocity = abs(distance) > 1 ? max(-20, min(20, velocity / distance)) : 0
        animation.duration = animation.settlingDuration
        layer.position.x = x
        layer.add(animation, forKey: "swipe")
    }
}
