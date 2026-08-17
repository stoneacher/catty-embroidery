import EmbroideryEngine

/// How the segment between two consecutive display-list entries is drawn.
///
/// A **relation between two stitches**, which is why it is a top-level type and
/// deliberately not nested on `PreviewStitch`. A `PreviewStitch` is a per-stitch
/// value stored up to 50 000 times and its doc comment already argues for staying
/// minimal; a nested `Segment` would read as "a stitch has a segment" and would
/// invite the stored property that puts a *derived* classification into an
/// append-only list — a second source of truth, and 50 k bytes to hold it. Always
/// computed, never stored.
///
/// (The story's criteria said "`PreviewStitch.Segment` already has all three
/// cases". No such type existed; US-305 created this one.)
public enum StitchSegmentStyle: Hashable, Sendable {
    /// Thread the machine sews. Drawn in the run's own colour, at a width that
    /// scales with the transform.
    case thread

    /// Machine travel: the stream would interpolate this move as jumps rather than
    /// stitching along it. Drawn distinctly — a deliberate deviation from *both*
    /// references, which draw travel as solid thread indistinguishable from
    /// stitching. It is **chrome, not design data**: the machine trims travel, so
    /// nothing about the thread's colour applies to it.
    case traversal

    /// Not drawn at all. Named `suppressed` and **not** `none`, though every line
    /// of the story called it that: `Optional.none` shadows a case of that name in
    /// any optional context, so `let style: StitchSegmentStyle? = .none` would
    /// compile and silently mean "no style" rather than "the suppressed style".
    case suppressed

    /// Classifies one segment. **The order of these three cases is load-bearing**,
    /// because a colour-run boundary and a traversal can coincide.
    ///
    /// 1. A **colour-run boundary** suppresses the segment, and it wins over
    ///    `.traversal`. This is a deliberate divergence, not Catroid parity:
    ///    Catroid's `colorChange` latch suppresses lines only until the next
    ///    *connecting* point resets it (`EmbroideryActor.kt:64-73`), and clause B's
    ///    second black point is connecting, so Catroid resets there and draws a
    ///    black connector. Our display list has no black transition point to hang
    ///    one on — it goes red → green directly — so drawing anything would imply
    ///    continuous thread across a swap the machine stopped for.
    /// 2. `.traversal` when the stream would interpolate the move as travel.
    /// 3. `.thread` otherwise.
    ///
    /// **"The colours differ" *is* "the run boundary", by construction**:
    /// `StitchDisplayList.append` opens a new run exactly when consecutive colours
    /// differ. That equivalence is checked differentially in
    /// `StitchSegmentStyleTests` rather than believed here — the same discipline
    /// `EmbroideryStream.requiresTraversal`'s own doc comment applies to its
    /// stream-state assumption.
    ///
    /// Note what `requiresTraversal` answers, because the obvious reading is wrong:
    /// it reports whether the stream would *interpolate*, so a move the stream
    /// **rejects outright** (ADR-020) comes back `false` and is drawn as ordinary
    /// thread — the preview draws a stitch the machine will never make. That is
    /// ADR-021 divergence #5, and it is pinned by a test rather than left to be
    /// discovered and "fixed".
    public static func classifying(from previous: PreviewStitch, to next: PreviewStitch) -> Self {
        if previous.color != next.color {
            return .suppressed
        }
        if EmbroideryStream.requiresTraversal(from: previous.position, to: next.position) {
            return .traversal
        }
        return .thread
    }
}
