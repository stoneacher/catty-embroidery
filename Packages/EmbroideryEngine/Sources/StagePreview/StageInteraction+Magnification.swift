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
    /// The floor is a **ratio**, never `StageTransform.minimumRepresentableScale`: that constant
    /// bounds a transform's scale, not a factor, and using it here narrowed the fit-aware range
    /// for a very small fit — the stage could not pinch down to a zoom the bounds explicitly
    /// permit (`/codex-review` round 2).
    func magnificationLimits(
        fitting fit: StageTransform,
        settlingAt progress: Double = 1
    ) -> ClosedRange<Double> {
        let scale = baseline(fitting: fit, settlingAt: progress).scale
        guard scale > 0, scale.isFinite else { return StageManipulation.unlimitedMagnification }

        let bounds = StageZoomBounds(fitting: fit)
        let lower = bounds.minimum / scale
        let upper = bounds.maximum / scale
        guard lower.isFinite, lower > 0, upper.isFinite else {
            return StageManipulation.unlimitedMagnification
        }
        return lower ... Swift.max(lower, upper)
    }
}
