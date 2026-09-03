import EmbroideryEngine
import Samples
import StagePreview
import Testing

/// US-310's *rule*: how far a live frame coarsens, and which designs it touches at all.
///
/// Split from `StitchDrawPlanCoarseningTests`, which asserts the shape of the resulting plan —
/// continuity, travel, colour runs, dots. The seam is real: everything here is arithmetic over
/// (count, threshold, target) and could be read off the story without opening a display list.
/// The split was *forced* by SwiftLint's 400-line file limit under `--strict`, which is the same
/// reason US-307 split `StageView`; keeping the two halves apart is worth it anyway.
@Suite("Stitch draw plan coarsening rule")
struct StitchDrawPlanCoarseningRuleTests {
    /// `count` stitches in one colour, ten units apart along x — every unit segment is
    /// `.thread`, so the stride is the only variable.
    private static func straightRun(_ count: Int) -> StitchDisplayList {
        displayList((0 ..< count).map { previewStitch(Double($0) * 10, 0, PreviewColor.red) })
    }

    private static func threadSegments(_ plan: StitchDrawPlan) -> [StitchDrawPlan.Segment] {
        plan.strokes.filter { $0.style == .thread }.flatMap(\.segments)
    }

    // MARK: - T2 · the stride rule, observed rather than restated

    /// **The rule is a public pure function and this test reads it back**, which is US-309's
    /// survivor lesson applied on day one: a test there that *restated* the settle rule instead
    /// of observing it passed the mutant, and that is why `PreviewRunState.settleWatermark(for:)`
    /// exists. Recomputing `(count - 1) / target + 1` here would assert the arithmetic against
    /// itself.
    ///
    /// The `target: .max` case is not decoration: the obvious spelling of a ceiling division,
    /// `(count + target - 1) / target`, **overflows and traps** there.
    @Test("the stride is one at or below the target and grows by ceiling division above it")
    func theStrideIsOneAtOrBelowTheTarget() {
        #expect(StitchDrawPlan.coarseningStride(forStitchCount: 0, target: 4000) == 1)
        #expect(StitchDrawPlan.coarseningStride(forStitchCount: 1, target: 4000) == 1)
        #expect(StitchDrawPlan.coarseningStride(forStitchCount: 3999, target: 4000) == 1)
        // The boundary: at exactly the target the stride is still 1. **What this case catches is
        // an off-by-one in the division, not the comparison** — checked by mutation rather than
        // assumed, because the first version of this comment claimed the opposite. `count /
        // target + 1` for `(count - 1) / target + 1` returns 2 here and fails; relaxing the
        // guard from `>` to `>=` is an *equivalent* mutant that no test can catch, since the
        // ceiling formula itself returns 1 at the boundary.
        #expect(StitchDrawPlan.coarseningStride(forStitchCount: 4000, target: 4000) == 1)
        #expect(StitchDrawPlan.coarseningStride(forStitchCount: 4001, target: 4000) == 2)
        #expect(StitchDrawPlan.coarseningStride(forStitchCount: 8000, target: 4000) == 2)
        #expect(StitchDrawPlan.coarseningStride(forStitchCount: 8001, target: 4000) == 3)
        #expect(StitchDrawPlan.coarseningStride(forStitchCount: 50000, target: 4000) == 13)
        #expect(StitchDrawPlan.coarseningStride(forStitchCount: 50001, target: 4000) == 13)
        #expect(StitchDrawPlan.coarseningStride(forStitchCount: .max, target: .max) == 1)
        // **Hostile targets, pinned** (`/codex-review` round 1, finding 4). The clamp to 1 is
        // load-bearing and was unasserted: deleting it leaves `target: 0` dividing by zero and
        // `target: -1` returning a stride of 0 — a stride of 0 means `spanned == stride` never
        // holds, so a run's thread is emitted as one span however long it is. This is a public
        // function whose own doc promises hostile input cannot kill the process.
        #expect(StitchDrawPlan.coarseningStride(forStitchCount: 2, target: 0) == 2)
        #expect(StitchDrawPlan.coarseningStride(forStitchCount: 2, target: -1) == 2)
        #expect(StitchDrawPlan.coarseningStride(forStitchCount: 0, target: 0) == 1)
        #expect(StitchDrawPlan.coarseningStride(forStitchCount: 50_000, target: .min) == 50_000)
    }

    /// **Two constants, because one cannot do both jobs — and the measurement is what showed
    /// it.** A single budget had to be simultaneously the floor below which nothing is coarsened
    /// (which must stay above the 3 194-stitch rosette, or a shipping design changes) and the
    /// segment count a large design aims for (which the simulator sweep put at ~1 000: stride 50
    /// brings the mid-gesture median from over two refresh periods to one, and stride 201 buys
    /// nothing further). Those are 3 194 ≤ x and x ≈ 1 000, which no single number satisfies.
    ///
    /// The visible consequence, recorded rather than hidden: the stride is **discontinuous** at
    /// the threshold — a 4 000-stitch design draws every stitch and a 4 001-stitch one strides
    /// by 5. It lasts only while a finger is down, and the alternative was a default that
    /// provably does not reach one frame period at 50 000.
    @Test("the threshold decides whether to coarsen and the target decides how much")
    func theThresholdDecidesWhetherAndTheTargetDecidesHowMuch() {
        // Just below and just at the threshold: untouched, whatever the target says.
        for count in [3_999, 4_000] {
            let list = Self.straightRun(count)
            #expect(
                StitchDrawPlan.coarse(of: list, threshold: 4_000, target: 1_000)
                    == StitchDrawPlan.entire(of: list)
            )
        }

        // Just above it: coarsened to the *target*, not to the threshold — the whole point of
        // separating them. A rule that reused the threshold as the target would stride by 2.
        let justOver = Self.straightRun(4_001)
        let plan = StitchDrawPlan.coarse(of: justOver, threshold: 4_000, target: 1_000)
        #expect(plan != StitchDrawPlan.entire(of: justOver))
        #expect(Self.threadSegments(plan).allSatisfy { $0.to - $0.from <= 5 })
        #expect(Self.threadSegments(plan).contains { $0.to - $0.from == 5 })
    }

    /// The shipped pair, asserted as a *relation* rather than as two literals: what matters is
    /// that no shipping design reaches the threshold and that the target is the smaller number.
    @Test("the shipped constants leave every sample alone and aim below the threshold")
    func theShippedConstantsLeaveEverySampleAlone() {
        #expect(StitchDrawPlan.liveSegmentTarget < StitchDrawPlan.liveCoarseningThreshold)
        #expect(StitchDrawPlan.coarseningStride(
            forStitchCount: 50_001, target: StitchDrawPlan.liveSegmentTarget
        ) == 51)
    }

    // MARK: - T11 · the shipping samples are untouched

    /// **What makes the constants themselves part of the contract.** Both shipping designs are
    /// at or below `liveCoarseningThreshold`, so every frame they draw — settled, live or mid-gesture — is exactly
    /// the plan they drew before this story. Iterating `SampleLibrary.all` rather than `.first`
    /// is deliberate: the existing plan suite uses `.first` and therefore covers only the
    /// 3 194-stitch rosette, leaving the 2 976-stitch coil unasserted (US-310, P13).
    @Test("no shipping sample is coarsened at the shipped constants")
    func noShippingSampleIsCoarsenedAtTheShippedConstants() throws {
        try #require(!SampleLibrary.all.isEmpty)

        for sample in SampleLibrary.all {
            var list = StitchDisplayList()
            var running = interpreter(sample.program)
            for events in tickBatches(&running) {
                list.append(contentsOf: RunBatch.reducing(events).stitches)
            }

            try #require(list.count > 1, "\(sample.id) must actually stitch")
            #expect(
                list.count <= StitchDrawPlan.liveCoarseningThreshold,
                "\(sample.id) has \(list.count) stitches, above the coarsening threshold"
            )
            #expect(StitchDrawPlan.coarse(of: list) == StitchDrawPlan.entire(of: list))
        }
    }
}
