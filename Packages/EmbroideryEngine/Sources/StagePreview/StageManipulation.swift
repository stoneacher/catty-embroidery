/// Two touch channels, reduced to one `StageGesture` — the input layer the stage was missing.
///
/// **What was wrong, and it was one thing, not two.** US-307 composed `MagnifyGesture` with
/// `DragGesture` and fed the drag's translation into `StageGesture.pan`. `DragGesture` is a
/// single-touch recogniser: with two fingers down its translation is not the centroid's, so
/// lateral movement during a pinch is largely dropped. The backlog entry blamed a second cause
/// as well — that `StageGesture`'s anchor is captured once, at gesture start, so content
/// "drifts away from under the touch" — and **that one is not a defect**. The frozen start
/// anchor is the correct formulation, and the live anchor it implies is *wrong*:
///
///     v(x₀) = m·(x₀ − a) + a + p                        (StageInteraction.moved)
///
/// Native manipulation requires each finger to keep the stage point it grabbed. For fingers at
/// centroid `c₀`, separation `d₀` at the start and `c₁`, `d₁` now, substituting `m = d₁/d₀`,
/// `a = c₀` and `p = c₁ − c₀` gives `v(x₀) = m·(x₀ − c₀) + c₁`, which is exactly where each
/// finger now is. Substituting the *live* centroid `a = c₁` instead leaves the result off by
/// `(1 − m)(c₁ − c₀)` — so implementing the entry as written would have introduced the drift it
/// was written to remove. The package math never needed changing; only its third input did.
///
/// **Why this is a value in `StagePreview` and not four pieces of `@State` in the view.**
/// ADR-028 rewrote the interaction layer after six review rounds found the same conceptual
/// mistake in four spellings, and its stated lesson is that the properties which matter must be
/// reachable by a test. Two UIKit recognisers make three new properties ambiguous — when a
/// manipulation is live, when it commits, and what happens when the system cancels it — so they
/// live here, where `swift test` can ask.
///
/// **This is also where ADR-028 partially retracts.** It claims the single commit "deletes
/// entirely" a state machine of captured baselines, rebasing and per-channel end bookkeeping.
/// Two recognisers have independent lifecycles — a pinch begins only at two touches and ends
/// when a finger lifts, while a pan with `maximumNumberOfTouches = 2` carries on with the other
/// — so the machine comes back. What changed is where it lives, and that ADR-028's own
/// `onlyTheFinalCumulativeValueIsApplied` (which collapsed to `once == once`, because "applied
/// exactly once" was a fact about a view) is finally assertable.
///
/// The single commit itself is **preserved**, which is what keeps ADR-030 §7's inherited
/// invariant satisfied rather than traded: `finish(in:)` yields a value exactly once, when the
/// last active channel ends, so `StageInteraction.settled` is written once per manipulation and
/// the settled raster re-bakes once, structurally.
public struct StageManipulation: Equatable, Sendable {
    /// One touch channel's lifecycle, asked of the recogniser rather than inferred from values.
    ///
    /// Three states, not a `Bool`: a channel that has *ended* is not the same as one that never
    /// began, because the value it left behind is still part of the manipulation. A pinch that
    /// ends while the pan continues must keep contributing its magnification, or the stage snaps
    /// back toward 1× in the middle of a gesture the user has not finished.
    private enum Channel: Equatable, Sendable {
        case absent
        case active
        case ended

        var isActive: Bool {
            self == .active
        }

        var hasBegun: Bool {
            self != .absent
        }
    }

    private var pinch: Channel = .absent
    private var pan: Channel = .absent

    /// Cumulative scale since the pinch began, latched at whatever the pinch last reported.
    private var magnification: Double = 1

    /// Where the pan recogniser's translation started, so a recogniser that begins away from
    /// zero contributes nothing until it actually moves.
    ///
    /// The shipped coordinator will zero the recogniser at `.began`, which is precisely why the
    /// tracker does not rely on it having done so: this half is the tested one, and an origin the
    /// untested half must remember is an invariant with nowhere to live.
    private var panOrigin: ViewPoint = .zero

    /// Cumulative centroid translation in view points, as the pan recogniser reports it,
    /// measured from `panOrigin`.
    ///
    /// `UIPanGestureRecognizer.translation(in:)` is the translation of the **centroid** of its
    /// touches and stays continuous when a finger is added or removed, which is the single
    /// property that makes the pair work and a hand-rolled recogniser subclass hard: rolling
    /// your own means re-implementing that re-basing, and getting it wrong is what visibly jumps.
    private var translation: ViewPoint = .zero

    /// The pinch's centre **in the baseline frame** — the centroid at pinch-begin, less whatever
    /// the pan had already moved by then.
    ///
    /// `nil` until a pinch begins. It does not follow the fingers *within* a pinch — a live
    /// anchor is wrong, not fresher (see the type comment) — but it is **re-derived when a new
    /// pinch begins**, because a manipulation can contain more than one.
    private var anchor: ViewPoint?

    /// The product of the pinches that have already ended in this manipulation.
    ///
    /// A recogniser's `scale` is cumulative from **its own** begin, and a coordinator resets it
    /// to 1 at `.began`, so a second pinch reports 1 where the manipulation is already at 3×.
    /// Without this the stage snaps back to unzoomed the instant the second finger lands.
    private var magnificationBase: Double = 1

    /// The compensation that keeps the frame still when the anchor is re-derived.
    ///
    /// Re-anchoring changes the composition even when the scale does not: `pinched(about:)` about
    /// a different point is a different transform, and the frame jumps by `(1 − m)(aNew − aOld)`.
    /// Accumulating that difference into the pan keeps the stage exactly where it was while
    /// letting the *next* pinch scale about the fingers the user actually has down.
    private var panOffset: ViewPoint = .zero

    public init() {}

    /// Whether any channel has begun and not yet been finished or cancelled.
    ///
    /// **Presence, not magnitude** — the question ADR-028 answered wrongly in four spellings.
    /// A pinch back to exactly 1× and a pan back to its origin are still a live manipulation,
    /// because the fingers are still down.
    public var isLive: Bool {
        pinch.hasBegun || pan.hasBegun
    }

    private var hasActiveChannel: Bool {
        pinch.isActive || pan.isActive
    }

    // MARK: - Reading

    /// The live gesture, or `nil` when no manipulation is in flight.
    ///
    /// Takes the viewport at *read* time rather than storing it, so the unit anchor is expressed
    /// against the same viewport `StageGesture.anchor(in:)` will multiply it back by. Storing one
    /// at pinch-begin would move the anchor if the device rotated mid-gesture.
    public func gesture(in viewport: ViewSize) -> StageGesture? {
        guard isLive else { return nil }

        let anchor = anchor ?? viewport.center
        return StageGesture(
            magnification: magnification,
            anchorUnitX: Self.unit(anchor.x, of: viewport.width),
            anchorUnitY: Self.unit(anchor.y, of: viewport.height),
            panX: translation.x + panOffset.x,
            panY: translation.y + panOffset.y
        )
    }

    /// A coordinate as a fraction of an extent, staying total for a viewport measured before
    /// layout settles — `StageTransform.fitting`'s house rule, applied to the one other place
    /// that divides by a viewport. Half means the centre, which is where a zoom with nowhere
    /// else to go belongs.
    private static func unit(_ coordinate: Double, of extent: Double) -> Double {
        guard extent > 0 else { return 0.5 }
        return coordinate / extent
    }

    // MARK: - The pinch channel

    /// A pinch begins — the first of the manipulation, or a later one after the user lifted a
    /// finger and put it back while still dragging with the other.
    ///
    /// **Re-anchoring without moving anything is the whole content of this method.** Three things
    /// have to happen at once: the anchor becomes the baseline-frame point currently under the
    /// fingers, the frame does not move, and the magnification already accumulated survives.
    ///
    /// The first pinch is the same arithmetic with `m == 1`, where the offset term vanishes and
    /// this reduces to `centroid − translation` — one code path rather than a special case, so
    /// the ordinary route cannot rot while the rare one is exercised only by tests.
    public mutating func pinchBegan(scale: Double, centroid: ViewPoint) {
        pinch = .active

        let previous = anchor ?? .zero
        let magnified = magnification
        if magnified.isFinite, magnified > 0 {
            // The baseline-frame point under the fingers now: invert `v(x) = m(x − a) + a + p`.
            let current = ViewPoint(
                x: (centroid.x - previous.x - translation.x - panOffset.x) / magnified + previous.x,
                y: (centroid.y - previous.y - translation.y - panOffset.y) / magnified + previous.y
            )
            // …and the pan term that makes the swap invisible. Derived by requiring
            // `m(x − aNew) + aNew + p + δ == m(x − aOld) + aOld + p` for every `x`.
            panOffset = ViewPoint(
                x: panOffset.x + (magnified - 1) * (current.x - previous.x),
                y: panOffset.y + (magnified - 1) * (current.y - previous.y)
            )
            anchor = current
        }

        magnificationBase = magnification
        magnification = magnificationBase * scale
    }

    public mutating func pinchChanged(to scale: Double) {
        guard pinch.isActive else { return }
        magnification = magnificationBase * scale
    }

    public mutating func pinchEnded() {
        guard pinch.isActive else { return }
        // Latch, so a pan continuing on the remaining finger keeps the zoom the user reached.
        magnificationBase = magnification
        pinch = .ended
    }

    // MARK: - The pan channel

    public mutating func panBegan(at translation: ViewPoint) {
        pan = .active
        panOrigin = translation
        self.translation = .zero
    }

    public mutating func panChanged(to translation: ViewPoint) {
        guard pan.isActive else { return }
        self.translation = ViewPoint(
            x: translation.x - panOrigin.x,
            y: translation.y - panOrigin.y
        )
    }

    public mutating func panEnded() {
        guard pan.isActive else { return }
        pan = .ended
    }

    // MARK: - Terminating

    /// The value to commit, or `nil` while any channel is still active.
    ///
    /// **Non-`nil` exactly once per manipulation**, and the caller may ask after every channel
    /// end without having to work out which one was last. Committing at the first end instead
    /// would write `StageInteraction.settled` twice for one manipulation, and so re-bake a
    /// 50 000-stitch prefix twice back to back at finger-lift — precisely where ADR-030 puts the
    /// residual tail.
    public mutating func finish(in viewport: ViewSize) -> StageGesture? {
        guard isLive, !hasActiveChannel, let gesture = gesture(in: viewport) else { return nil }
        self = StageManipulation()
        return gesture
    }

    /// The system took the touches away — an incoming call, a competing recogniser, the view
    /// going away mid-gesture.
    ///
    /// **Nothing is committed**, and the tracker is cleared. SwiftUI clears a `@GestureState` for
    /// this case on its own; a UIKit coordinator does not, and missing it leaves the stage
    /// permanently live: `canUseRaster` false forever, the design coarse forever, and the settled
    /// raster never rebuilt. That is a worse failure than the one this type exists to fix, which
    /// is why it has its own test on both sides of the boundary.
    public mutating func cancelled() {
        self = StageManipulation()
    }
}
