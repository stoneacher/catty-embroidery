#if DEBUG
    /// Counts `CanvasStitchLayers` draw passes, so a frame-time capture can say whether the
    /// renderer ran at all during it.
    ///
    /// **This exists because a `CADisplayLink` callback is not evidence of a rendered frame.**
    /// The link fires once per display refresh regardless of what the app submitted; SwiftUI
    /// redraws a `Canvas` only when something invalidates it. On a settled 50 000-stitch stage
    /// nothing does — no run is advancing, no gesture is live — so a ten-second capture can come
    /// back `p99 16.7 · PASS` having asked the renderer for **zero** frames. That number would
    /// describe the display's refresh cadence, which is not in question, rather than ADR-009's
    /// claim, which is (Codex round 1, finding 1).
    ///
    /// A capture now reports `draws` beside `n`, so the reader can tell a measurement of the
    /// renderer from a measurement of the display. `FrameTimeStatistics` deliberately does not
    /// take this value — it is a property of the *app* during a window, not of the durations —
    /// and the readout labels a capture with too few draws rather than scoring it.
    ///
    /// A main-actor global rather than a value threaded through the view tree: the counter is
    /// written inside a `Canvas` drawing closure and read by an overlay that is a sibling of the
    /// stage, so plumbing it would mean hoisting the recorder out of `FrameTimeReadout` and
    /// passing a hook through `StagePreviewRenderer` — changing the shape of production types
    /// for a debug instrument. It is `#if DEBUG`, non-observable and written by exactly one
    /// closure on one actor, so the usual objections to a global do not bite here.
    @MainActor
    enum StageDrawCounter {
        private(set) static var count = 0

        /// One draw pass. Deliberately not `@Observable`: a published mutation per draw would
        /// invalidate the view that reads it and drive further draws, which is the feedback loop
        /// US-309's readout was already caught in once (I3).
        static func record() {
            count += 1
        }
    }
#endif
