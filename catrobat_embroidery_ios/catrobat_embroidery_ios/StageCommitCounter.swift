#if DEBUG
    /// Counts committed manipulations, so a frame-time capture can say how many gesture-ends it
    /// contained.
    ///
    /// **It exists to make one comparison an observation instead of an inference.** ADR-030
    /// leaves the tail explicitly unclaimed and points at the gesture-end commit and its full
    /// re-bake; ADR-029 names this counter as the cheapest thing that would tell the two apart.
    /// The story's device captures #1 and #2 differ only in how many times the user lets go —
    /// one sustained manipulation against several short ones — so if p99 and the worst frame
    /// scale with `commits=` rather than with `drawn=`, the commit hypothesis is confirmed and
    /// the residual belongs to rung 1. Without the number the comparison is an argument about
    /// how many drags the tester thinks they performed.
    ///
    /// A near-copy of `StageDrawCounter`, deliberately: a main-actor global, non-`@Observable`
    /// so a mutation cannot invalidate the view that caused it, and `#if DEBUG` so it does not
    /// exist in any build a user can install.
    ///
    /// **Its only call site is a closure the view supplies**, not the coordinator, and that is a
    /// testability decision rather than a stylistic one: the coordinator is driven directly by a
    /// suite that runs in parallel with the serialized suite asserting on this counter, so the
    /// coordinator tests wire their own closure and never reach here.
    ///
    /// **That is not full isolation, and the first version of this comment claimed it was**
    /// (`swift-code-reviewer`, I6). `StageManipulationWiringTests` hosts the real `StageCanvas`,
    /// whose closure *is* `record` under `DEBUG`, so a hosted commit does increment this. What
    /// makes that safe today is the same argument `FrameTimeDrawAccountingTests` already records
    /// for `StageDrawCounter`: every body involved is synchronous and `@MainActor`, so the two
    /// suites cannot interleave, and each capture takes its own baseline at `start()` so the
    /// absolute value never matters. **The day one of those tests gains an `await`, the delta
    /// becomes nondeterministic** — that is the cost of a process-wide counter, stated rather
    /// than wished away.
    @MainActor
    enum StageCommitCounter {
        private(set) static var count = 0

        /// One committed manipulation — one `StageInteraction.settled` write, and therefore one
        /// re-bake of the settled prefix.
        static func record() {
            count += 1
        }
    }
#endif
