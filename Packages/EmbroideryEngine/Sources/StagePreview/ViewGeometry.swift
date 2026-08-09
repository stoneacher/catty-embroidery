/// A point in view space: origin top-left, y **down**, measured in the view's
/// own points.
///
/// StagePreview is Foundation-only (ADR-022), so view space needs its own type
/// rather than `CGPoint` — the app bridges these in its `CGAffineTransform`
/// adapter (US-305). The separate type is not merely a stand-in: having stage
/// and view points be different types is what stops a y-up coordinate being
/// passed where a y-down one is expected, which is the mistake `StageTransform`
/// confines its single flip to prevent.
public struct ViewPoint: Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = ViewPoint(x: 0, y: 0)
}

/// A view's size in its own points. Only `StageTransform.fitting` consumes it —
/// the two mapping directions are viewport-free, because the translation
/// already carries wherever the content was placed.
public struct ViewSize: Hashable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}
