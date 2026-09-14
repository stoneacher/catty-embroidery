/// What is happening to the stage right now — extracted from `StageInteraction.swift`.
///
/// The split was forced by SwiftLint's 400-line file limit under `--strict` when US-313a added
/// the toggle and the directional pan, the same forcing function that split
/// `StitchDrawPlanCoarseningRuleTests`. `Phase` is the piece that moves because it is the only
/// part of the type that needs nothing `private` — the transitions all write `settled`, whose
/// setter is `private(set)` on purpose, and widening that to move them would give away the
/// invariant this whole story rests on: `settled` is not written while fingers are down.
public extension StageInteraction {
    /// What is happening to the stage right now.
    ///
    /// Deliberately **not** a `Bool` pair or a set of optionals: a gesture and a fit animation
    /// are mutually exclusive by construction here, where before they could overlap and the
    /// code that composed them had to decide which won.
    public enum Phase: Equatable, Sendable {
        case idle
        /// A double-tap or the "Fit to Hoop" action, animating from one transform to another.
        ///
        /// **`id` is identity, not bookkeeping, and leaving it out was a real defect.** The
        /// rewrite claimed that making `finishSettling` idempotent replaced the generation
        /// token it deleted. It does not: idempotence protects a late completion only when
        /// *nothing* is settling, and cannot tell "my animation" from "a newer one". Begin A,
        /// interrupt it with a gesture, begin B, and A's completion then finds B's `.settling`
        /// phase and ends it early (Codex round 7). The token was never bookkeeping — it was
        /// ownership — and the improvement over the original is that it now lives *inside the
        /// value*, where a test can reach it, rather than as a `@State` counter in a view.
        ///
        /// **`adoptsFit` is why the double-tap could become a toggle.** Every animation used to
        /// end at the fit, so `finishSettling` could simply clear `settled` and go back to
        /// following it. US-313's zoom-in half animates *away* from the fit, and clearing
        /// `settled` there would snap the stage back the instant the spring finished — the zoom
        /// would last exactly as long as the animation. Carried in the phase rather than
        /// inferred by comparing `to` against the fit, because that comparison is the
        /// equality-of-transforms question this whole type exists to stop asking: it is
        /// defeated by one ULP, and ADR-028 records four spellings of it losing in a row.
        case settling(
            id: Int,
            from: StageTransform,
            to: StageTransform,
            progress: Double,
            adoptsFit: Bool
        )
    }
}
