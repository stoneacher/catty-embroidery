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
    /// The stitch count above which a *live* frame starts joining stitches together.
    ///
    /// Below it nothing changes at all: both shipping designs (2 976 and 3 194 stitches) draw
    /// every stitch in every window, exactly as they did before this story, which
    /// `StitchDrawPlanCoarseningTests` asserts by plan equality over `SampleLibrary.all`.
    ///
    /// **Separate from `liveSegmentTarget`, because one number could not do both jobs — and it
    /// took a measurement to see that.** A single "budget" had to be at once the floor that
    /// keeps the 3 194-stitch rosette untouched (so ≥ 3 194) and the segment count a large
    /// design should aim for (which the sweep put near 1 000). Those two requirements have no
    /// common value. Measured mid-gesture at 50 001 stitches, drawn frames only, on the
    /// simulator: uncoarsened median 36.1 ms; at a target of 4 000 (stride 13) 33.3 ms — still
    /// two refresh periods; at 1 000 (**stride 51**) **16.667 ms, one period**; at 250 (stride
    /// 201) 16.667 ms again.
    ///
    /// **What that does and does not establish** (`swift-code-reviewer`): stride 51 gets the
    /// median under one period and stride 201 reads no better. It does **not** locate a knee —
    /// an earlier version of this comment said so — because a display-link interval reports only
    /// multiples of the refresh period, so 51 and 201 both read the floor and are
    /// indistinguishable; the transition lies anywhere in (13, 51]. 1 000 is preferred over 250
    /// on fidelity grounds, which needs no knee.
    ///
    /// The consequence, recorded rather than hidden: the stride is **discontinuous here**. A
    /// 4 000-stitch design draws every stitch and a 4 001-stitch one strides by 5. It lasts only
    /// while a finger is down, and the alternative was a default that provably does not reach
    /// one frame period at 50 000 stitches.
    static let liveCoarseningThreshold = 4_000

    /// Roughly how many segments a live frame should draw once it is coarsening at all.
    ///
    /// **A knob, and honest about it.** 1 000 is where the simulator sweep above stops
    /// improving, not a proof about any device: the numbers that decide it are part CPU and part
    /// GPU, and ADR-029 records that the balance point cannot be located headlessly. The device
    /// session sweeps it, and the story requires at least two values.
    ///
    /// Raising it buys fidelity at the cost of frame time; lowering it does the reverse and stops
    /// helping below ~1 000. It has no effect at all on designs at or below
    /// `liveCoarseningThreshold`.
    static let liveSegmentTarget = 1_000

    /// How many stitch intervals one drawn segment may join, for a design of `count` stitches
    /// aiming at `target` segments: `1` at or below the target, `ceil(count/target)` above it.
    ///
    /// **Public and pure, deliberately, and this is US-309's most useful result applied on day
    /// one.** A test there *restated* the settle rule instead of observing it and therefore
    /// passed a mutant of the code it was meant to pin; the fix was to make the rule a function
    /// a test can call. This is that shape from the start.
    ///
    /// Spelled `count <= target ? 1 : (count - 1) / target + 1` rather than the more familiar
    /// `(count + target - 1) / target`, which **overflows and traps** at `target == Int.max` — a
    /// public entry point must not have an input that kills the process.
    ///
    /// **Not the trap ADR-029 records for the proportional settle chunk.** That failed because a
    /// threshold tracking a continuously growing count moved a *watermark with a side effect* on
    /// nearly every batch, turning fifty rasterisations into 176. This parameterises a pure
    /// per-frame function whose result is thrown away: nothing is cached on it and nothing is
    /// triggered by its changing (at the shipped target it changes ~50 times across a
    /// 50 000-stitch run, and each change costs one plan that was going to be built anyway). The
    /// coupling that *would* recreate that trap is rung 3 — a `Path` cache keyed on the plan is
    /// invalidated whenever this changes — so rung 3 must key on the plan including the stride
    /// and expect those invalidations.
    ///
    /// **Whether to coarsen at all is not this function's decision**; that is
    /// `liveCoarseningThreshold`, applied by `coarse(of:threshold:target:)`. Keeping them apart
    /// is what lets the device session tune fidelity without changing *which* designs are
    /// affected.
    static func coarseningStride(forStitchCount count: Int, target: Int) -> Int {
        let target = Swift.max(1, target)
        guard count > target else { return 1 }
        return (count - 1) / target + 1
    }

    /// Everything in the list, joined into roughly `target` segments and dots.
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
    /// **The bound is not `target`**, and pretending otherwise would be a false claim: every
    /// colour run must close its own span and keep its own dot, and traversals are never joined,
    /// so the counts are `ceil(count/stride) + colorRuns (+ traversals)`. A design that changes
    /// colour every stitch — ADR-029's one genuinely growing axis — is therefore **not helped by
    /// this rung at all**. Rungs 3 and 4 are where that case goes.
    static func coarse(
        of list: StitchDisplayList,
        threshold: Int = liveCoarseningThreshold,
        target: Int = liveSegmentTarget
    ) -> StitchDrawPlan {
        planning(
            list,
            dotting: 0 ..< list.count,
            segmentsFrom: 0,
            upTo: lastSegment(before: list.count),
            // At or below the threshold this is 1, and the plan is `entire`'s — the same
            // segments and dots in the same order, which is the claim that survives the
            // representation change from index to pair (`/codex-review` round 2).
            stride: list.count > threshold
                ? coarseningStride(forStitchCount: list.count, target: target)
                : 1
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
        threshold: Int = liveCoarseningThreshold,
        target: Int = liveSegmentTarget
    ) -> StitchDrawPlan {
        guard transform.canUseRaster else {
            return coarse(of: list, threshold: threshold, target: target)
        }
        return compositingRaster ? live(of: list) : entire(of: list)
    }
}
