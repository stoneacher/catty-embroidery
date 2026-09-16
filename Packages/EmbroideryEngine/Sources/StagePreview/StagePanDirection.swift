/// Which way a directional pan accessibility action moves the **viewport**.
///
/// A named quartet rather than SwiftUI's `AccessibilityAdjustmentDirection` for the reason
/// `StageZoomAdjustment` gives — `StagePreview` is Foundation-only (ADR-022) — and for a second
/// one that matters more here: the *sign* is the whole difficulty, and a sign that lives in a
/// view is a sign no test can ask about.
///
/// **The convention is camera-relative, and it is a decision rather than an obvious reading.**
/// `.left` means the viewport moves left, so more of the design's left-hand side becomes visible
/// and the content itself slides *right*. Every spoken or typed direction works this way —
/// "scroll down" shows you what is further down, and the arrow keys in Maps, Photos and Preview
/// are all camera-relative. The opposite, content-relative reading exists only in gesture APIs
/// (`UIAccessibilityScrollDirection`, a three-finger swipe), where the user's own hand supplies
/// the direction and nothing is spoken. **A named action is a word, so it takes the word's
/// convention.** (Sebastian's decision, 2026-09-16; `StagePanDirectionTests` asserts it the way
/// a user would check it, by looking at what comes into view.)
///
/// The gesture pan is unaffected: a finger still drags the content with it, because there the
/// hand is the word.
public enum StagePanDirection: Hashable, Sendable, CaseIterable {
    case left
    case right
    case up
    case down

    /// How far one activation moves, as a fraction of the viewport on the axis it names.
    ///
    /// **A viewport fraction carries no scale term, and that is the property rather than a
    /// simplification**: the delta is in view points, so a quarter of the viewport is a quarter
    /// of *what the user can see* at every zoom — at 50× it covers a fiftieth of the stage
    /// distance it covers at the fit. The step is zoom-adaptive by construction, where
    /// `StageInteraction.adjustmentStep` had to be multiplicative to achieve the same thing.
    ///
    /// A quarter, and not more, keeps three quarters of the previous view on screen: a picture
    /// of stitches has no landmarks, so a larger step disorients rather than saving activations.
    /// The price is stated rather than hidden — corner to corner is about four activations at
    /// the fit but roughly forty at 10×, which is a treadmill. The fix for that is the deferred
    /// pan-clamping story, not a bigger number here (ADR-028 ships the pan unclamped and says
    /// so, and `StageInteraction.panned(by:)` refuses to clamp for one caller).
    public static let accessibilityFraction: Double = 0.25

    /// The delta to hand `StageInteraction.panned(by:)`, in view points.
    ///
    /// Positive `y` moves the content **down**, because `StageTransform.dragged(by:)` is pure
    /// y-down view space — `pinched` is the only method that flips — so revealing what sits
    /// above the viewport means a positive `y`. Deriving that through `flippingY` is the mistake
    /// waiting here, and it is why the vertical pair has its own test.
    ///
    /// Total for a viewport measured before layout settles: a zero or non-finite extent yields a
    /// zero step rather than a `NaN`, which `dragged(by:)` would refuse anyway — but refusing
    /// late leaves the caller unable to tell "nothing to move by" from "something went wrong".
    public func step(in viewport: ViewSize) -> ViewPoint {
        switch self {
        case .left: ViewPoint(x: Self.distance(across: viewport.width), y: 0)
        case .right: ViewPoint(x: -Self.distance(across: viewport.width), y: 0)
        case .up: ViewPoint(x: 0, y: Self.distance(across: viewport.height))
        case .down: ViewPoint(x: 0, y: -Self.distance(across: viewport.height))
        }
    }

    private static func distance(across extent: Double) -> Double {
        guard extent.isFinite, extent > 0 else { return 0 }
        return extent * accessibilityFraction
    }
}
