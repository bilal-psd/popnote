import QuartzCore

/// Shared animation timing, so every motion in Popnote feels the same.
enum Motion {
    /// A strong ease-out: most of the movement happens right away, so the
    /// UI responds instantly and then settles. The built-in `.easeOut` is too weak.
    static let easeOut = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
}
