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

    /// There are stitches, **or a run is in flight**. The renderer draws.
    case drawn

    static func resolving(hasSelection: Bool, hasStitches: Bool, isRunning: Bool) -> Self {
        // Stitches win over the absence of a selection: not reachable today, since
        // nothing clears a selection and only a selected sample produces stitches, but
        // total rather than trapping — and it resolves toward showing what is actually
        // there rather than claiming nothing is selected while a design is on screen.
        //
        // **A run in flight also wins, even with nothing stitched yet** (US-306). A script
        // whose first bricks are `wait` emits nothing for its first ticks, and without
        // this the canvas would show the press-play state while the button beneath it read
        // "Stop" — a screen contradicting itself. Not reachable with the bundled samples,
        // since sample 1 emits 51 stitches on its first tick, which is why this needed a
        // test rather than a screenshot to find.
        if hasStitches || isRunning {
            return .drawn
        }
        return hasSelection ? .notRun : .noSelection
    }
}
