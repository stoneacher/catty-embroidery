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
        self.init(
            minimum: Swift.min(fit.scale, StageTransform.minimumScale),
            maximum: StageTransform.maximumScale
        )
    }

    /// The fit-aware bounds, widened to include a transform the stage is **already at**.
    ///
    /// **Only ever widens, which is this type's existing rule applied to a second input.** A
    /// design settled below the current floor is reachable without anything going wrong: pan an
    /// out-of-hoop design at a narrow viewport, where the floor is the fit's own small scale,
    /// then widen the viewport so the fit — and its floor — grow past where the user is. The
    /// bounds then excluded the transform on screen, so the *next* pinch snapped the stage up to
    /// the floor, and a pinch of exactly 1× did it too.
    ///
    /// That last part is what made this worth fixing rather than documenting. US-313a's
    /// `StageInteraction.magnificationLimits` clamps the input layer into the same range so the
    /// tracker and the transform agree on one factor (`/codex-review` round 1) — and clamping a
    /// 1× pinch up to 1.25× turns an identity gesture into a non-identity one, which defeats
    /// `StageGesture.isIdentity` and with it every guard ADR-028 built on top of it
    /// (`/codex-review` round 4).
    public init(fitting fit: StageTransform, including current: Double) {
        let fitted = StageZoomBounds(fitting: fit)
        guard current.isFinite, current > 0 else { self = fitted; return }

        self.init(
            minimum: Swift.min(fitted.minimum, current),
            maximum: Swift.max(fitted.maximum, current)
        )
    }

    /// Clamps into these bounds.
    ///
    /// Direction-preserving at the infinities and NaN → `minimum`, exactly as
    /// `StageTransform.clampedScale` is, and for the same reason: mapping every
    /// non-finite value to the floor turned an enormous zoom *in* into the maximum zoom
    /// *out* (US-302, Codex round 5).
    public func clamping(_ scale: Double) -> Double {
        guard !scale.isNaN else { return minimum }
        return Swift.min(Swift.max(scale, minimum), maximum)
    }
}
