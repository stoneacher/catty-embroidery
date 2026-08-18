/// The scale range a **gesture** may reach — deliberately not the range a
/// `StageTransform` may hold.
///
/// `StageTransform` already separates those two ideas: `minimumScale` (0.05) is the
/// gesture bound and `minimumRepresentableScale` (1e-6) is the floor every transform
/// must satisfy, and US-305's Codex round 2 was the story of what happens when the two
/// are conflated — a fitted design wider than `available / 0.05` was cropped off-canvas
/// by a *zoom* limit.
///
/// This type closes the other half of that gap. `fitting` floors at the representable
/// scale, so a legitimately out-of-hoop design can be **fitted** below the gesture
/// minimum; a pinch clamped to the absolute 0.05 would then snap it *larger* on the
/// user's first touch, and double-tap-to-fit followed by a pinch-out could never get
/// back. The case is reachable and exports perfectly well — `StageTransform.minimumScale`
/// documents it: `(0,0) → (-3201,0) → (3201,0)` spans 6402 stage points, needs a scale of
/// about 0.04499, and its DST extents are ±6402 units, inside the 4-wide header fields.
///
/// **The bound only ever widens.** `minimum` is `min(fit, minimumScale)`, never `max`, so
/// nothing that a pinch could reach before becomes unreachable now. That is what lets
/// `pinched(by:about:)`'s seven rounds of hardened invariants keep their meaning
/// unchanged — every existing test asserts the same property it always did, because
/// `gestureDefault` *is* the old behaviour.
///
/// The alternative considered was `minimum = fit.scale` — "never zoom out past the fit",
/// which is arguably the nicer interaction. Rejected: it *narrows* the range for every
/// in-hoop design, which silently changes what `StageTransformTests.scaleClampsAtBothEnds`
/// means, and it would make `StageTransform.minimumScale` dead code.
public struct StageZoomBounds: Equatable, Sendable {
    public let minimum: Double
    public let maximum: Double

    /// The bound `pinched(by:about:)` has always applied, so the two-argument overload
    /// keeps its exact previous behaviour. Pinned equal to `StageTransform.clampedScale`
    /// by a differential test rather than by inspection — two spellings of one rule is
    /// where a later edit fixes one and forgets the other.
    public static let gestureDefault = StageZoomBounds(
        minimum: StageTransform.minimumScale,
        maximum: StageTransform.maximumScale
    )

    /// Private, so `minimum ≤ maximum` cannot be violated from outside. The only public
    /// way in derives both from a transform whose own fields the `StageTransform`
    /// chokepoint has already made finite and in range.
    private init(minimum: Double, maximum: Double) {
        self.minimum = minimum
        self.maximum = maximum
    }

    /// Floors at whichever is lower — the fit or the gesture minimum.
    ///
    /// `fit.scale` is guaranteed finite and within `[minimumRepresentableScale,
    /// maximumScale]` by `StageTransform.init`, so no sanitising is needed here and none
    /// is done: a second clamp would be a second place to disagree.
    public init(fitting fit: StageTransform) {
        // Red-phase stub.
        self.init(minimum: 0, maximum: 0)
        _ = fit
    }

    /// Clamps into these bounds.
    ///
    /// Direction-preserving at the infinities and NaN → `minimum`, exactly as
    /// `StageTransform.clampedScale` is, and for the same reason: mapping every
    /// non-finite value to the floor turned an enormous zoom *in* into the maximum zoom
    /// *out* (US-302, Codex round 5).
    public func clamping(_ scale: Double) -> Double {
        // Red-phase stub.
        _ = scale
        return 0
    }
}
