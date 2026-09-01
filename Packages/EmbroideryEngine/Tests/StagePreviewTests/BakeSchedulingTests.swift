import StagePreview
import Testing

/// US-309 AC5: the re-rasterisation policy, tuned by measurement.
///
/// **The story asks for the wrong thing here and this suite measures the right one.** AC5
/// names "the mid-gesture blit from US-307"; ADR-028's correction deleted that blit, so
/// there is nothing to tune under that name. What US-307 actually left behind is a bake
/// *schedule*, and it is quadratic:
///
/// `PreviewRunState.apply` advances the watermark in fixed `settleChunk` steps, and
/// `CanvasStitchLayers.onChange(of: bakeKey)` re-plans and re-rasterises **the whole settled
/// prefix** on every advance. Total work to n stitches is therefore Σ chunk·k = Θ(n²/chunk):
/// ~50 full rasterisations on the way to 50 000 at today's `settleChunk = 1000`.
///
/// Two consequences, and the second is what AC3's "no frame exceeds 33.3 ms" exists to
/// catch. First, the total is 5–6× larger than it needs to be. Second, the **last** bake of
/// a long run is a full 50 000-segment offscreen render landing on one frame — a dropped
/// frame near the end of every long run, invisible in any capture taken after the design has
/// settled.
///
/// This suite pins the shape and the chosen constant *together*, which is AC5's real
/// requirement: a bare tuned number would be the magic constant the criterion forbids.
@Suite("US-309 bake scheduling", .serialized, .timeLimit(.minutes(1)))
struct BakeSchedulingTests {
    /// The watermarks a run actually bakes at, **observed** by driving a real
    /// `PreviewRunState` and recording every distinct value of `settledCount`.
    ///
    /// Observed rather than derived, and that distinction was found by mutation rather than
    /// by reasoning: the first version of this helper restated the quantisation rule, and a
    /// mutant that quantised `apply` to three chunks instead of one **passed** it, because
    /// the test and the code were computing the same wrong thing from the same constant.
    /// Its doc comment claimed it was derived from `PreviewRunState`'s own rule. It was not.
    private func observedWatermarks(reaching count: Int) -> [Int] {
        var run = PreviewRunState()
        run.begin()
        var seen: [Int] = []
        let stitches = SyntheticDesign.stitches(count: count)
        for start in stride(from: 0, to: stitches.count, by: 250) {
            let slice = Array(stitches[start ..< min(start + 250, stitches.count)])
            run.apply(RunUpdate(batch: RunBatch(stitches: slice)))
            if run.display.settledCount > 0, seen.last != run.display.settledCount {
                seen.append(run.display.settledCount)
            }
        }
        return seen
    }

    /// The watermarks a *hypothetical* chunk would bake at.
    ///
    /// A model, and labelled one: `settleChunk` is a `static let`, so the tuning comparison
    /// below cannot observe an alternative policy the way `observedWatermarks` observes the
    /// shipped one. It is used only where the two chunks are compared against each other, so
    /// a shared error cancels rather than misleads.
    private func modelledWatermarks(reaching count: Int, chunk: Int) -> [Int] {
        var seen: [Int] = []
        for total in stride(from: chunk, through: count, by: chunk) {
            let settled = total - total % chunk
            if settled > 0, seen.last != settled {
                seen.append(settled)
            }
        }
        return seen
    }

    /// The number of full rasterisations a 50 000-stitch run pays for.
    ///
    /// **Recorded as a number rather than argued about**, because "a handful of times per
    /// run" is what `PreviewRunState.settleChunk`'s own doc comment claims and fifty is not
    /// a handful. That claim was measured against M3's real samples, which reach 3 194
    /// stitches and bake three times; it does not survive the design this story exists to
    /// run.
    /// **The bake count, recorded as the number it is.**
    ///
    /// `settleChunk`'s own comment said the raster is rebuilt "a handful of times per run".
    /// That was measured against M3's 3 194-stitch samples, where it is three; at the scale
    /// this story exists to run it is **fifty**, and the last of them plans the entire
    /// design on one frame. The two tests below are the measurement AC5 asks for; this one
    /// pins what the shipped policy actually does, so the device session has a baseline to
    /// tune against rather than a claim.
    @Test("a fifty-thousand-stitch run bakes once per settle chunk")
    func aFiftyThousandStitchRunBakesOncePerSettleChunk() {
        let bakes = observedWatermarks(reaching: 50_000)

        #expect(bakes.count == 50_000 / PreviewRunState.settleChunk)
        #expect(bakes.first == PreviewRunState.settleChunk)
        #expect(bakes.last == PreviewRunState.settleWatermark(for: 50_000))
        // Fifty is not a handful. Stated as an expectation rather than a comment so the
        // sentence cannot quietly stop being true.
        #expect(bakes.count > 10, "\(bakes.count) bakes — the 'handful' claim does not survive 50k")
    }

    /// The live tail the shipped policy leaves is bounded by a **constant**, not a fraction.
    ///
    /// This is the half of the trade-off that argues *for* the fixed chunk, and it is why
    /// US-309 did not raise it on the headless evidence alone: the per-frame cost ADR-009
    /// claims is small is exactly this tail, and a geometric schedule — which would bound
    /// the bake count — buys that by letting the tail reach a third of the design.
    @Test("the shipped policy leaves a live tail bounded by a constant")
    func theShippedPolicyLeavesALiveTailBoundedByAConstant() {
        for count in [3_194, 6_000, 20_000, 50_000, 200_000] {
            let tail = count - PreviewRunState.settleWatermark(for: count)
            #expect(tail < PreviewRunState.settleChunk,
                    "a \(count)-stitch design left a \(tail)-stitch live tail")
        }
    }

    /// The total settled-plan work across a whole run, as a function of the chunk.
    ///
    /// This is the measurement AC5 asks to justify the constant with. The plan is the cheap
    /// half of a bake — the rasterisation it drives scales identically and costs far more —
    /// so the ratio between chunks is the number that transfers, not the absolute.
    @Test("a larger settle chunk costs proportionally less total bake work")
    func aLargerSettleChunkCostsProportionallyLessTotalBakeWork() {
        let full = SyntheticDesign.displayList(count: 50_000)

        let atThousand = totalPlanWork(over: full, chunk: 1_000)
        let atFiveThousand = totalPlanWork(over: full, chunk: 5_000)
        let ratio = seconds(atThousand) / seconds(atFiveThousand)

        #expect(
            ratio >= 3,
            """
            total settled-plan work to 50 000: chunk 1 000 → \(milliseconds(atThousand)), \
            chunk 5 000 → \(milliseconds(atFiveThousand)), ratio \
            \(String(format: "%.2f", ratio))× — Θ(n²/chunk) predicts 5×
            """
        )
    }

    /// The spike, isolated: the last bake of a 50 000-stitch run plans the whole design.
    ///
    /// Bounded against the *first* bake rather than against a wall clock, so the assertion
    /// is about the shape and cannot flake.
    @Test("the last bake of a long run plans the whole design")
    func theLastBakeOfALongRunPlansTheWholeDesign() {
        let full = SyntheticDesign.displayList(count: 50_000)
        let first = settledPlanCost(of: full, upTo: PreviewRunState.settleChunk)
        let last = settledPlanCost(of: full, upTo: 50_000)
        let ratio = seconds(last) / seconds(first)

        #expect(
            ratio >= 10,
            """
            first bake \(milliseconds(first)), last bake \(milliseconds(last)), \
            \(String(format: "%.1f", ratio))× — the last bake is the frame at risk of \
            exceeding AC3's 33.3 ms, and it lands near the end of every long run
            """
        )
    }

    /// The tuned chunk must still leave the watermark reaching the full count, or a run
    /// ends with an unbaked tail and "50 000 settled" is unreachable — the precondition
    /// AC3's capture protocol depends on.
    @Test("the watermark reaches the full count for the synthetic design")
    func theWatermarkReachesTheFullCountForTheSyntheticDesign() {
        var run = PreviewRunState()
        run.begin()
        let stitches = SyntheticDesign.displayList(count: 50_000).stitches
        for batch in stride(from: 0, to: stitches.count, by: 500) {
            let slice = Array(stitches[batch ..< min(batch + 500, stitches.count)])
            run.apply(RunUpdate(batch: RunBatch(stitches: slice)))
        }
        #expect(run.display.count == 50_000)
        #expect(run.display.settledCount == PreviewRunState.settleWatermark(for: 50_000))
    }

    private func totalPlanWork(over list: StitchDisplayList, chunk: Int) -> Duration {
        let marks = modelledWatermarks(reaching: list.count, chunk: chunk)
        return fastest {
            for mark in marks {
                var settled = list
                settled.markSettled(upTo: mark)
                blackHole(StitchDrawPlan.settled(of: settled))
            }
        }
    }

    private func settledPlanCost(of list: StitchDisplayList, upTo mark: Int) -> Duration {
        var settled = list
        settled.markSettled(upTo: mark)
        return fastest { blackHole(StitchDrawPlan.settled(of: settled)) }
    }
}
