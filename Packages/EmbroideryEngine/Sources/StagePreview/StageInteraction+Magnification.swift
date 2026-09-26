/// The magnification range the input layer needs in order to agree with the transform.
///
/// In its own file because `StageInteraction.swift` crossed SwiftLint's 400-line limit under
/// `--strict` — and this is the piece that can move: it only *reads*. The toggle and the
/// directional pan would be the more natural extraction, but both write `settled`, whose setter
/// is `private(set)` so that one file owns the invariant "settled is not written while fingers
/// are down"; moving them would mean widening it to `internal(set)` and giving that away.
public extension StageInteraction {
    /// What a live pinch may multiply the baseline by, as a ratio, before
    /// `StageTransform.pinched` starts clamping.
    ///
    /// **Exists so the input layer and the transform agree on the factor.**
    /// `StageManipulation` compensates its rebase with the magnification it holds, and that is
    /// exact only if the transform applies the same number; `pinched` clamps into
    /// `StageZoomBounds`, which is fit-aware and therefore not something the tracker can know.
    /// Handing the range over keeps one source of truth for the bound instead of two spellings
    /// of it (`/codex-review` round 1).
    ///
    /// - Parameter settlingAt: the fit animation's **visible** progress, as every other method
    ///   here takes it. ADR-028 records that the model's progress jumps to 1 the moment
    ///   `withAnimation` runs and only the view's `Animatable` shim holds the interpolated value
    ///   — so without this the range is computed against the animation's *destination* while the
    ///   user pinches against what is on screen, and round 1's clamped-rebase jump comes back by
    ///   another route (`/codex-review` round 2).
    ///
    /// **Precondition since US-314: ask straight after `beginManipulating`.** Inside a
    /// manipulation the range is computed against the frozen fit, not `fit`, and a frozen fit
    /// that outlived its manipulation would be returned to any other caller. The coordinator
    /// is the only caller and always asks in that order.
    ///
    /// The floor is a **ratio**, never `StageTransform.minimumRepresentableScale`: that constant
    /// bounds a transform's scale, not a factor, and using it here narrowed the fit-aware range
    /// for a very small fit — the stage could not pinch down to a zoom the bounds explicitly
    /// permit (`/codex-review` round 2).
    func magnificationLimits(
        fitting fit: StageTransform,
        settlingAt progress: Double = 1
    ) -> ClosedRange<Double> {
        // The frozen fit, unconditionally: the coordinator asks only after `beginManipulating`,
        // which has just captured or kept it — and a pinch re-beginning mid-manipulation must be
        // clamped against the fit its frames are drawn at (US-314).
        let fit = manipulationFit ?? fit
        let scale = baseline(fitting: fit, settlingAt: progress).scale
        guard scale > 0, scale.isFinite else { return StageManipulation.unlimitedMagnification }

        // The same widened bounds `moved(by:from:fitting:in:)` applies, so the range the tracker
        // is clamped into and the range the transform enforces are one thing rather than two
        // spellings that can disagree — which is the whole reason this method exists.
        let bounds = StageZoomBounds(fitting: fit, including: scale)
        let lower = bounds.minimum / scale
        let upper = bounds.maximum / scale
        guard lower.isFinite, lower > 0, upper.isFinite else {
            return StageManipulation.unlimitedMagnification
        }
        return lower ... Swift.max(lower, upper)
    }

    /// How far the stage is zoomed relative to the fit — 1.0 means fitted.
    ///
    /// Relative, because this is what gets spoken: view points per stage point means nothing to
    /// a user, and "300 per cent" is something they can act on.
    func magnification(
        gesture: StageGesture?,
        fitting fit: StageTransform,
        in viewport: ViewSize
    ) -> Double {
        // Divides by the fit on screen, not the frozen one, deliberately: after the commit the
        // spoken value is `settled.scale / fit.scale`, so dividing by the frozen fit mid-gesture
        // would make the number jump at finger-lift.
        transform(with: gesture, fitting: fit, in: viewport).scale / fit.scale
    }
}
