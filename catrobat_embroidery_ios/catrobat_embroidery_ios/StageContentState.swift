/// What the stage is showing. A pure function of two facts, so the branch is
/// assertable without a view.
///
/// **There are two empty states and they are not interchangeable** — the story asks for
/// a "press play" state, and the app already had a "nothing selected" one that must
/// survive. Collapsing them would tell a user who has selected nothing to press play,
/// and a user who has selected a design that they have not selected a design.
enum StageContentState: Hashable {
    /// Reachable only in the regular-width detail column, which exists before anything
    /// has been picked (`RootView`). Keeps US-303's `ContentUnavailableView`.
    case noSelection

    /// A design is chosen and has not run. **Not a loading state** — see `StageView`.
    case notRun

    /// There are stitches. The renderer draws.
    case drawn

    static func resolving(hasSelection: Bool, hasStitches: Bool) -> Self {
        // Stitches win over the absence of a selection: not reachable today, since
        // nothing clears a selection and only a selected sample produces stitches, but
        // total rather than trapping — and it resolves toward showing what is actually
        // there rather than claiming nothing is selected while a design is on screen.
        if hasStitches {
            return .drawn
        }
        return hasSelection ? .notRun : .noSelection
    }
}
