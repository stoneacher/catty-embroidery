/// ADR-029's fallback ladder, **rung 2**: the window a frame draws while no raster may be
/// composited.
///
/// **Why this rung and not rung 1.** US-309 measured the shipped renderer on an iPhone 17 Pro:
/// animating to 50 000 stitches passes (p99 16.670 ms, no dropped frame) and **mid-gesture fails
/// at a median of 69.1 ms** — about 14 fps. Rung 1 tunes `settleChunk`, which governs *baking*,
/// and the gesture path never bakes: ADR-028 removed the mid-gesture blit deliberately, so while
/// an interaction is live `StageRenderTransform.canUseRaster` is `false` and every frame takes
/// `.entire(of:)` over the whole design. Rung 1 cannot touch that; this can.
///
/// **The premise was measured before this file was written.** Mid-gesture, on one instrument
/// with the same draw count at both counts, 3 194 stitches costs one frame period or less while
/// 50 001 costs 36.129 ms — so at least 57 % of the mid-gesture frame scales with the stitch
/// count, and at most ~15 ms of it does not. A cost that had turned out to be a fixed per-frame
/// overhead would have made coarsening useless, and the decision rule said so in advance
/// (`docs/user-stories/milestone-3/US-310-coarsen-mid-gesture-draw-plan.md`, "Premise").
public extension StitchDrawPlan {
    /// How many stitches a *live* frame may plan before it starts joining them.
    ///
    /// **A knob, and honest about it.** The value is arithmetic rather than an optimum: 12.5×
    /// below 50 000, above both shipping samples (2 976 and 3 194, so neither is affected at
    /// all), above the renderer's own 2 000-stitch baking threshold, and at the resulting stride
    /// of 13 the premise decomposition predicts 36.1 ms → ≲ 17.3 ms on the machine it was
    /// measured on. Where the *balance* between fidelity and frame time actually sits depends on
    /// GPU work no `swift test` can see, exactly as ADR-029 records for `settleChunk`, so this
    /// is the device session's first knob and the story requires a sweep of at least two values.
    ///
    /// Raising it is safe in the sense that nothing breaks; it simply buys back fidelity at the
    /// cost of frame time. Lowering it below a shipping sample's stitch count would start
    /// coarsening designs that render perfectly well today, which `StitchDrawPlanCoarseningTests`
    /// forbids.
    static let liveStitchBudget = 4000

    /// How many stitch intervals one drawn segment may join, for a design of `count` stitches.
    ///
    /// `1` at or below the budget — so ordinary designs are untouched — and `ceil(count/budget)`
    /// above it.
    ///
    /// **Public and pure, deliberately, and this is US-309's most useful result applied on day
    /// one.** A test there *restated* the settle rule instead of observing it and therefore
    /// passed a mutant of the code it was meant to pin; the fix was to make the rule a function
    /// a test can call. This is that shape from the start.
    ///
    /// Spelled `count <= budget ? 1 : (count - 1) / budget + 1` rather than the more familiar
    /// `(count + budget - 1) / budget`, which **overflows and traps** at `budget == Int.max` —
    /// a public entry point must not have an input that kills the process.
    ///
    /// **Not the trap ADR-029 records for the proportional settle chunk.** That failed because a
    /// threshold tracking a continuously growing count moved a *watermark with a side effect* on
    /// nearly every batch, turning fifty rasterisations into 176. This parameterises a pure
    /// per-frame function whose result is thrown away: nothing is cached on it and nothing is
    /// triggered by its changing (at the default budget it changes 12 times across a
    /// 50 000-stitch run). The coupling that *would* recreate that trap is rung 3 — a `Path`
    /// cache keyed on the plan is invalidated whenever this changes — so rung 3 must key on the
    /// plan including the stride and expect those dozen invalidations.
    static func coarseningStride(forStitchCount count: Int, budget: Int) -> Int {
        let budget = Swift.max(1, budget)
        guard count > budget else { return 1 }
        return (count - 1) / budget + 1
    }

    /// Everything in the list, joined into at most `budget`-ish segments and dots.
    ///
    /// The same window as `.entire` — the whole list, no raster underneath — at a stride above
    /// 1. It is *not* "every k-th segment": the thread stays continuous, because a dropped
    /// segment would show as blank fabric and a joined one does not. What it costs instead is
    /// fidelity: the drawn route may deviate from the true path by up to the largest excursion
    /// within `stride` consecutive stitches, and the image visibly changes at interaction start
    /// and again at commit. That pop is the accepted trade, and it is the same class of trade
    /// ADR-028 already took when it accepted that off-screen content is revealed only as frames
    /// re-stroke.
    ///
    /// **The bound is not `budget`**, and pretending otherwise would be a false claim: every
    /// colour run must close its own span and keep its own dot, and traversals are never joined,
    /// so the counts are `ceil(count/stride) + colorRuns (+ traversals)`. A design that changes
    /// colour every stitch — ADR-029's one genuinely growing axis — is therefore **not helped by
    /// this rung at all**. Rungs 3 and 4 are where that case goes.
    static func coarse(of list: StitchDisplayList, budget: Int = liveStitchBudget) -> StitchDrawPlan {
        planning(
            list,
            dotting: 0 ..< list.count,
            segmentsFrom: 0,
            upTo: lastSegment(before: list.count),
            stride: coarseningStride(forStitchCount: list.count, budget: budget)
        )
    }

    /// The window this frame should draw, given what the stage is doing.
    ///
    /// **The choice lives here rather than in the renderer, and that is the point of the
    /// function.** The app's equivalent branch was "did we get a usable raster?", which is a
    /// different question: that branch is also taken when the settled prefix is simply too short
    /// to bake, or the bake key is stale, or the `Canvas` is not the size the raster was
    /// rendered at — none of which is an interaction, and none of which should cost fidelity.
    /// Keying on `canUseRaster` says what is actually meant, and putting it in the package puts
    /// it on the fast gate (ADR-023) instead of in a `private` SwiftUI view where only a hosted,
    /// drawn `Canvas` could observe it.
    ///
    /// The liveness guard comes **first**, so a caller that passes `compositingRaster: true`
    /// alongside a live transform still gets the coarse plan: a raster baked at `bake` cannot be
    /// composited under a tail stroked at `current`, so that combination is a caller's mistake
    /// rather than a state to honour.
    ///
    /// **`canUseRaster == false` is a gesture *or* the fit animation** — `StageInteraction`
    /// reports `.live` while a gesture is in flight *or* while the fit spring is settling — and
    /// both are per-frame full re-strokes, so both want the coarse window. The double-tap
    /// settle is also the only deterministic way to put this plan on screen for a screenshot.
    static func forFrame(
        of list: StitchDisplayList,
        at transform: StageRenderTransform,
        compositingRaster: Bool,
        budget: Int = liveStitchBudget
    ) -> StitchDrawPlan {
        guard transform.canUseRaster else { return coarse(of: list, budget: budget) }
        return compositingRaster ? live(of: list) : entire(of: list)
    }
}
