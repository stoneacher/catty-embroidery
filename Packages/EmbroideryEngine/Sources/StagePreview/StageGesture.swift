/// A gesture's state, **absolute since it began** — the shape SwiftUI actually delivers.
///
/// `MagnifyGesture.Value.magnification` and `DragGesture.Value.translation` are both cumulative
/// from the gesture's start, not per-callback deltas, so this is a snapshot rather than
/// something to accumulate. Folding each callback in as a delta compounds it: a pinch whose
/// callbacks read 2, 2, 2 lands at 8× for fingers that only ever asked for 2×.
///
/// Foundation-only (ADR-022): the anchor arrives from SwiftUI as a `UnitPoint` and the pan as a
/// `CGSize`, and both are reduced to `Double`s at the app boundary so no CoreGraphics or SwiftUI
/// type crosses into the package.
public struct StageGesture: Equatable, Sendable {
    /// Cumulative scale factor since the gesture began. 1 means the fingers have not pinched.
    public var magnification: Double

    /// The pinch's centre, as a fraction of the viewport on each axis.
    public var anchorUnitX: Double
    public var anchorUnitY: Double

    /// Cumulative drag translation in view points, **including** the recognizer's threshold
    /// distance. Not subtracted anywhere: the live frame and the committed transform are then
    /// the same number by construction, rather than two pieces of code that have to agree.
    public var panX: Double
    public var panY: Double

    public init(
        magnification: Double = 1,
        anchorUnitX: Double = 0.5,
        anchorUnitY: Double = 0.5,
        panX: Double = 0,
        panY: Double = 0
    ) {
        self.magnification = magnification
        self.anchorUnitX = anchorUnitX
        self.anchorUnitY = anchorUnitY
        self.panX = panX
        self.panY = panY
    }

    /// Whether the fingers have, on balance, done nothing.
    ///
    /// **Asked of the inputs, which is the only place it can be asked exactly.** Every earlier
    /// spelling of this question compared *transforms* — `current == committed`,
    /// `live != LiveGesture()`, `next != fit` — and each was defeated in turn, the last by a
    /// single ULP, because re-deriving a transform through a different expression does not
    /// reproduce its bits. A tolerance would have been the next patch and the wrong one.
    public var isIdentity: Bool {
        magnification == 1 && panX == 0 && panY == 0
    }

    public func anchor(in viewport: ViewSize) -> ViewPoint {
        ViewPoint(unitX: anchorUnitX, unitY: anchorUnitY, in: viewport)
    }

    public var pan: ViewPoint {
        ViewPoint(x: panX, y: panY)
    }
}
