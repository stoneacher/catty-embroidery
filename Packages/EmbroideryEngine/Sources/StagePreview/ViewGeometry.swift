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

    /// A point given as a fraction of `viewport` on each axis.
    ///
    /// Exists so that the *view* never multiplies. SwiftUI hands a pinch's centre over as a
    /// `UnitPoint`, and `MagnifyGesture`'s anchor has to become a `ViewPoint` before
    /// `StageTransform.pinched(by:about:)` can use it; reading two `Double`s off a
    /// `UnitPoint` is not arithmetic, whereas multiplying them by a measured size is — and
    /// US-307's first criterion puts transform arithmetic in the package, not the view.
    ///
    /// Takes two `Double`s rather than a `UnitPoint` because `StagePreview` is
    /// Foundation-only (ADR-022): naming a SwiftUI type here would break the isolation test
    /// that makes that boundary checkable instead of aspirational.
    public init(unitX: Double, unitY: Double, in viewport: ViewSize) {
        self.init(x: unitX * viewport.width, y: unitY * viewport.height)
    }
}

/// A view's size in its own points.
///
/// The two *mapping* directions remain viewport-free — the translation already carries
/// wherever the content was placed — but this type is no longer read by `fitting` alone, as
/// an earlier version of this comment said: US-307 added `StageZoom.adjust(_:fitting:in:)`
/// and `ViewPoint(unitX:unitY:in:)`, each of which needs the viewport to place something
/// relative to its centre (`swift-code-reviewer`).
public struct ViewSize: Hashable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    /// A viewport measured before layout settles. `StageTransform.fitting`
    /// stays total for it.
    public static let zero = ViewSize(width: 0, height: 0)

    /// The viewport's middle — where a zoom with no finger behind it is anchored.
    ///
    /// Named `center` to match `StageBox.center` rather than the British spelling used in
    /// prose, so the two geometry types read the same way at a call site.
    public var center: ViewPoint {
        ViewPoint(x: width / 2, y: height / 2)
    }
}
