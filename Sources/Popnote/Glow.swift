import AppKit

/// A soft halo of colour bleeding out around a window, played once and
/// removed. The panel can't draw past its own edges, so the halo lives in a
/// click-through window just behind it that moves with it.
final class GlowWindow: NSWindow {
    /// Room around the panel for the halo to fade out in.
    private static let margin: CGFloat = 32
    /// Close to the panel's own corners; the blur hides any difference.
    private static let cornerRadius: CGFloat = 12

    private let container = CALayer()
    /// A tight bright rim, a body, and a wide soft halo.
    private let rim = CALayer(), body = CALayer(), halo = CALayer()

    /// Glows around `panel` in `color`, then goes away.
    static func flash(around panel: NSWindow, color: NSColor) {
        GlowWindow(around: panel, color: color).play(around: panel)
    }

    private init(around panel: NSWindow, color: NSColor) {
        let frame = panel.frame.insetBy(dx: -Self.margin, dy: -Self.margin)
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        collectionBehavior = panel.collectionBehavior

        let view = NSView(frame: NSRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        contentView = view

        let bounds = view.bounds
        let outline = CGPath(roundedRect: bounds.insetBy(dx: Self.margin, dy: Self.margin),
                             cornerWidth: Self.cornerRadius, cornerHeight: Self.cornerRadius, transform: nil)
        var cgColor = color.cgColor
        panel.effectiveAppearance.performAsCurrentDrawingAppearance { cgColor = color.cgColor }
        // Only the shadows draw: the layers have no content of their own.
        for (edge, radius) in [(halo, 12.0), (body, 6.0), (rim, 2.0)] {
            edge.frame = bounds
            edge.shadowPath = outline
            edge.shadowColor = cgColor
            edge.shadowOffset = .zero
            edge.shadowRadius = radius
            edge.shadowOpacity = 1
            container.addSublayer(edge)
        }
        // Cut out the panel's area, so a translucent panel doesn't show a tint.
        let mask = CAShapeLayer()
        let cutout = CGMutablePath()
        cutout.addRect(bounds)
        cutout.addPath(outline)
        mask.path = cutout
        mask.fillRule = .evenOdd
        container.mask = mask
        container.frame = bounds
        container.opacity = 0
        view.layer?.addSublayer(container)
    }

    /// Eases in over 300ms, then dissolves slowly over 600ms while the halo
    /// spreads a little, like light fading out.
    private static let rise = 0.3, fall = 0.6
    /// How bright it gets at the top: a hint of colour, not a flare.
    private static let peak = 0.6
    /// Starts softly and glides to the top, instead of popping on.
    private static let brighten = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1)
    /// A gentle ease-out, for the halo's spread.
    private static let swell = CAMediaTimingFunction(controlPoints: 0.33, 1, 0.68, 1)
    /// Lingers at the top, then lets go smoothly instead of dropping off.
    private static let dissolve = CAMediaTimingFunction(controlPoints: 0.37, 0, 0.63, 1)

    private func play(around panel: NSWindow) {
        panel.addChildWindow(self, ordered: .below) // follows the panel if it moves
        let duration = Self.rise + Self.fall

        let pulse = CAKeyframeAnimation(keyPath: "opacity")
        pulse.values = [0, Self.peak, 0]
        pulse.keyTimes = [0, NSNumber(value: Self.rise / duration), 1]
        pulse.timingFunctions = [Self.brighten, Self.dissolve]
        pulse.duration = duration

        // The spread is the only change that isn't opacity; Reduce Motion skips it.
        let spread = CABasicAnimation(keyPath: "shadowRadius")
        spread.fromValue = 8
        spread.toValue = 16
        spread.duration = duration
        spread.timingFunction = Self.swell

        // A new window takes a frame to reach the screen; start after it, so
        // the rise isn't cut short.
        let start = CACurrentMediaTime() + 1.0 / 60
        CATransaction.begin()
        CATransaction.setCompletionBlock { [self] in
            panel.removeChildWindow(self)
            orderOut(nil)
        }
        for (animation, layer) in [(pulse as CAAnimation, container), (spread, halo)] {
            animation.beginTime = layer.convertTime(start, from: nil)
            animation.fillMode = .backwards
            if animation === spread && NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { continue }
            layer.add(animation, forKey: "popnote.glow")
        }
        CATransaction.commit()
    }
}
