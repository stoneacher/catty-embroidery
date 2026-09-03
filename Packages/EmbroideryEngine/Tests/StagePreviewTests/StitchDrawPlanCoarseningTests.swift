import EmbroideryEngine
import Samples
import StagePreview
import Testing

/// US-310: the coarse window a frame draws while `canUseRaster` is false — ADR-029's fallback
/// ladder, rung 2.
///
/// **Why coarsening rather than the "draw every k-th segment" ADR-029's rung 2 says.** Dropping
/// segments dashes the thread: k−1 stitch lengths of blank fabric between every drawn segment,
/// and no saving at all on the dots, which are plausibly the larger half of the cost (one
/// `addEllipse` is four cubics against a line segment's one). Coarsening joins stitch `a → b`
/// instead, so the thread stays continuous through subsampled vertices. `T4` is the test that
/// pins the difference, and the mutation it rejects is precisely the ADR's literal wording.
///
/// **What every bound here is measured against.** The premise was checked before this file
/// existed: mid-gesture, on one instrument with the same draw count, 3 194 stitches costs one
/// frame period or less and 50 001 costs 36.129 ms, so at least 57 % of the frame scales with
/// the stitch count (US-310, "Premise"). A fixed per-frame overhead would have predicted equal
/// medians and this file would not exist.
///
/// **These are structural assertions, never timings.** The planner still classifies every unit
/// segment — it must, or it draws thread across a jump — so headless *planning* time barely
/// moves; the saving is in the renderer, which `swift test` cannot see. Five wall-clock ratios
/// on this project have already been refuted by CI; a sixth at a 0.045 ms denominator would be
/// the worst of them.
@Suite("Stitch draw plan coarsening")
struct StitchDrawPlanCoarseningTests {
    // MARK: - Fixtures

    private static let twoShortRuns = displayList([
        previewStitch(0, 0, PreviewColor.red),
        previewStitch(10, 0, PreviewColor.red),
        previewStitch(20, 0, PreviewColor.red),
        previewStitch(30, 0, PreviewColor.green),
        previewStitch(40, 0, PreviewColor.green)
    ])

    private static let firstRunWithALongGap = displayList([
        previewStitch(0, 0, PreviewColor.red),
        previewStitch(10, 0, PreviewColor.red),
        previewStitch(200, 0, PreviewColor.red),
        previewStitch(210, 0, PreviewColor.red),
        previewStitch(220, 0, PreviewColor.green),
        previewStitch(230, 0, PreviewColor.green)
    ])

    private static let onlyTraversals = displayList([
        previewStitch(0, 0, PreviewColor.red),
        previewStitch(200, 0, PreviewColor.red),
        previewStitch(400, 0, PreviewColor.red)
    ])

    /// `count` stitches in one colour, ten units apart along x — every unit segment is
    /// `.thread`, so coarsening is the only variable.
    private static func straightRun(_ count: Int) -> StitchDisplayList {
        displayList((0 ..< count).map { previewStitch(Double($0) * 10, 0, PreviewColor.red) })
    }

    /// Every segment of a plan, flattened — the plan's coverage, independent of how it grouped
    /// the segments into strokes.
    private static func segments(_ plan: StitchDrawPlan) -> [StitchDrawPlan.Segment] {
        plan.strokes.flatMap(\.segments)
    }

    private static func threadSegments(_ plan: StitchDrawPlan) -> [StitchDrawPlan.Segment] {
        plan.strokes.filter { $0.style == .thread }.flatMap(\.segments)
    }

    private static func dottedIndices(_ plan: StitchDrawPlan) -> [Int] {
        plan.dots.flatMap { Array($0.dottedIndices) }.sorted()
    }

    // MARK: - T1 · the identity that keeps one planner behind three windows

    /// **Vacuous on its own, and deliberately kept anyway.** An implementation that ignored the
    /// budget entirely passes this; it is discriminating only paired with `T3` and `T10`, which
    /// require the budget to be respected above it. What it buys is the property that makes
    /// `StitchDrawPlan+Planning.swift`'s "one planner parameterised by two windows, rather than
    /// three implementations" argument survive this story: `coarse` at an unreachable budget
    /// *is* `entire`, so the coarse path cannot drift into a second set of rules for the same
    /// pixels.
    @Test("at an unreachable budget the coarse plan is the entire plan")
    func atAnUnreachableBudgetTheCoarsePlanIsTheEntirePlan() {
        let fixtures = [
            StitchDisplayList(),
            displayList([previewStitch(0, 0, PreviewColor.red)]),
            Self.twoShortRuns,
            Self.firstRunWithALongGap,
            Self.onlyTraversals,
            Self.straightRun(200)
        ]

        for list in fixtures {
            #expect(StitchDrawPlan.coarse(of: list, budget: .max) == StitchDrawPlan.entire(of: list))
        }
    }

    // MARK: - T2 · the stride rule, observed rather than restated

    /// **The rule is a public pure function and this test reads it back**, which is US-309's
    /// survivor lesson applied on day one: a test there that *restated* the settle rule instead
    /// of observing it passed the mutant, and that is why `PreviewRunState.settleWatermark(for:)`
    /// exists. Recomputing `(count - 1) / budget + 1` here would assert the arithmetic against
    /// itself.
    ///
    /// The `budget: .max` case is not decoration: the obvious spelling of a ceiling division,
    /// `(count + budget - 1) / budget`, **overflows and traps** there.
    @Test("the stride is one at or below the budget and grows by ceiling division above it")
    func theStrideIsOneAtOrBelowTheBudget() {
        #expect(StitchDrawPlan.coarseningStride(forStitchCount: 0, budget: 4000) == 1)
        #expect(StitchDrawPlan.coarseningStride(forStitchCount: 1, budget: 4000) == 1)
        #expect(StitchDrawPlan.coarseningStride(forStitchCount: 3999, budget: 4000) == 1)
        // The boundary: at exactly the budget nothing is coarsened. `<` for `<=` here is the
        // one-character mutation this case exists to catch.
        #expect(StitchDrawPlan.coarseningStride(forStitchCount: 4000, budget: 4000) == 1)
        #expect(StitchDrawPlan.coarseningStride(forStitchCount: 4001, budget: 4000) == 2)
        #expect(StitchDrawPlan.coarseningStride(forStitchCount: 8000, budget: 4000) == 2)
        #expect(StitchDrawPlan.coarseningStride(forStitchCount: 8001, budget: 4000) == 3)
        #expect(StitchDrawPlan.coarseningStride(forStitchCount: 50000, budget: 4000) == 13)
        #expect(StitchDrawPlan.coarseningStride(forStitchCount: 50001, budget: 4000) == 13)
        #expect(StitchDrawPlan.coarseningStride(forStitchCount: .max, budget: .max) == 1)
    }

    // MARK: - T3 · the bound, two-sided

    /// **Two-sided on purpose.** An upper bound alone is passed by a `coarse` that returns
    /// nothing at all — the failure mode this project has already met once, in
    /// `StitchDrawPlanScalingTests`, where a plan that drew less than it should have satisfied
    /// every bound it was given.
    ///
    /// The bound is stated as what it actually is rather than as "≤ budget": every colour run
    /// must close its own span and keep its own dot, so the counts carry a `+ colorRuns` term
    /// and the segment count also carries the traversals, which are **never** coarsened.
    /// `fineTraversalCount` is therefore read off the fine plan rather than assumed to be zero.
    @Test("above the budget the plan is bounded by the stride, and is not empty")
    func aboveTheBudgetThePlanIsBoundedByTheStride() {
        let list = SyntheticDesign.displayList(count: 50000, colorRuns: 5)
        let budget = 4000
        let stride = StitchDrawPlan.coarseningStride(forStitchCount: list.count, budget: budget)

        let fine = StitchDrawPlan.entire(of: list)
        let fineTraversals = fine.strokes.filter { $0.style == .traversal }.flatMap(\.segments).count
        let plan = StitchDrawPlan.coarse(of: list, budget: budget)

        let expected = (list.count + stride - 1) / stride
        let threads = Self.threadSegments(plan).count
        let dots = plan.dots.reduce(0) { $0 + $1.count }

        #expect(threads <= expected + list.colorRuns.count + fineTraversals)
        #expect(dots <= expected + list.colorRuns.count)
        // The other side: a plan that drew nothing would pass both bounds above.
        #expect(threads >= 3000)
        #expect(dots >= 3000)
    }

    // MARK: - T4 · continuity, which is the whole of decision 1

    @Test("the coarse thread is continuous, not every k-th segment")
    func theCoarseThreadIsContinuous() throws {
        let list = Self.straightRun(200)
        let plan = StitchDrawPlan.coarse(of: list, budget: 10)
        let segments = Self.threadSegments(plan)

        try #require(segments.count > 1, "otherwise continuity is trivially satisfied")
        #expect(segments.first?.from == 0)
        #expect(segments.last?.to == list.count - 1)
        // No gaps: each segment starts where the previous one ended. Dashing — the literal
        // reading of ADR-029's rung 2 — fails here and nowhere else in this file.
        for (earlier, later) in zip(segments, segments.dropFirst()) {
            #expect(earlier.to == later.from)
        }
        // And it really is coarser than the fine plan, or the assertion above is met by k = 1.
        #expect(segments.count < list.count - 1)
        #expect(segments.allSatisfy { $0.to - $0.from <= 10 })
    }

    // MARK: - T5 · no thread across travel

    /// ADR-024 records that **both** references draw travel as solid thread indistinguishable
    /// from stitching, so a machine's travel moves look sewn, and that we deliberately do not.
    /// Coarsening is the one change that could reintroduce it by accident: a span joining
    /// `a → b` over a jump would draw exactly the line the references draw.
    ///
    /// Asserted through the public classifier over the list's own stitches, so the test does not
    /// re-implement the rule it is checking.
    @Test("no coarse thread segment spans a traversal, and traversals stay unmerged")
    func noCoarseThreadSegmentSpansATraversal() throws {
        // Twenty short moves, one long hop, twenty more — one colour throughout, so the hop is
        // a traversal rather than a suppressed colour boundary.
        var stitches = (0 ..< 20).map { previewStitch(Double($0) * 10, 0, PreviewColor.red) }
        stitches.append(previewStitch(1000, 0, PreviewColor.red))
        stitches += (0 ..< 20).map { previewStitch(1000 + Double($0 + 1) * 10, 0, PreviewColor.red) }
        let list = displayList(stitches)

        let plan = StitchDrawPlan.coarse(of: list, budget: 8)

        for segment in Self.threadSegments(plan) {
            for index in segment.from ..< segment.to {
                let style = StitchSegmentStyle.classifying(
                    from: list.stitches[index], to: list.stitches[index + 1]
                )
                #expect(style == .thread, "segment \(segment.from)→\(segment.to) spans a \(style)")
            }
        }

        // The traversal itself is still drawn, and drawn as one unit segment: merging two jumps
        // would erase the needle penetration between them.
        let traversals = plan.strokes.filter { $0.style == .traversal }.flatMap(\.segments)
        #expect(traversals == [StitchDrawPlan.Segment(from: 19, to: 20)])
        try #require(!Self.threadSegments(plan).isEmpty)
    }

    // MARK: - T6 · no span crosses a colour run

    @Test("no coarse segment crosses a colour run boundary")
    func noCoarseSegmentCrossesAColourRunBoundary() throws {
        let list = SyntheticDesign.displayList(count: 20000, colorRuns: 4)
        let plan = StitchDrawPlan.coarse(of: list, budget: 1000)

        try #require(list.colorRuns.count == 4)
        for stroke in plan.strokes {
            for segment in stroke.segments {
                let owner = list.colorRuns.first { $0.range.contains(segment.from) }
                let run = try #require(owner, "segment \(segment.from) belongs to no colour run")
                #expect(run.range.contains(segment.to), "segment crosses out of its run")
                #expect(stroke.color == run.color)
            }
        }
    }

    // MARK: - T7 · every colour run keeps a dot

    /// **The anchoring decision, made assertable.** A global `index % stride == 0` rule skips an
    /// entire run shorter than the stride, and what the user sees is a thread colour vanishing
    /// the instant a finger lands. Anchoring the stride at each run's own `lowerBound` makes
    /// "every run keeps at least one dot" true by construction — including at run length 1,
    /// where a global rule loses all but every k-th colour.
    @Test("every colour run keeps at least one dot, whatever the stride")
    func everyColourRunKeepsAtLeastOneDot() throws {
        for runs in [1000, 50000] {
            let list = SyntheticDesign.displayList(count: 50000, colorRuns: runs)
            let plan = StitchDrawPlan.coarse(of: list, budget: 4000)

            try #require(list.colorRuns.count == runs)
            #expect(plan.dots.count == list.colorRuns.count)

            for (dotRun, colorRun) in zip(plan.dots, list.colorRuns) {
                let dotted = Array(dotRun.dottedIndices)
                #expect(!dotted.isEmpty)
                #expect(dotted.first == colorRun.range.lowerBound)
                #expect(dotted.allSatisfy { colorRun.range.contains($0) })
            }
        }
    }

    // MARK: - T8 · the exact dot count

    /// Structural, not timed: the hatch fixture's row spacing is shorter than its stitch length,
    /// so it contains no traversal and the dot count is decided by the stride alone.
    @Test("the dot count is the per-run ceiling of the stride")
    func theDotCountIsThePerRunCeilingOfTheStride() {
        let list = SyntheticDesign.displayList(count: 50000, colorRuns: 5)
        let budget = 4000
        let stride = StitchDrawPlan.coarseningStride(forStitchCount: list.count, budget: budget)
        let plan = StitchDrawPlan.coarse(of: list, budget: budget)

        let expected = list.colorRuns.reduce(0) { total, run in
            total + (run.range.count + stride - 1) / stride
        }

        #expect(plan.dots.reduce(0) { $0 + $1.count } == expected)
        #expect(Self.dottedIndices(plan).count == expected, "count and dottedIndices must agree")
    }

    // MARK: - T9 · which window a frame gets

    /// **The window choice belongs in the package, not in the renderer.** The app's `else`
    /// branch is taken both while an interaction is live *and* whenever there simply is no
    /// valid raster — below the baking threshold, or on a key or viewport mismatch — and only
    /// the first of those is a reason to coarsen. Keying on the branch would coarsen a settled
    /// stage that merely has no cache yet.
    ///
    /// **Asserted above the budget deliberately.** At or below it `coarse == entire`, so three
    /// of the four rows would compare the same value and the test would assert nothing (US-310
    /// planning correction P14).
    @Test("a frame gets the coarse window exactly while the transform is live")
    func aFrameGetsTheCoarseWindowExactlyWhileTheTransformIsLive() {
        var list = SyntheticDesign.displayList(count: 50000, colorRuns: 5)
        list.markSettled(upTo: 49000)
        let budget = 4000

        let fit = StageTransform(scale: 1, translation: .zero)
        let zoomed = StageTransform(scale: 3, translation: ViewPoint(x: 10, y: 20))
        let live = StageRenderTransform.live(bake: fit, current: zoomed)
        let settled = StageRenderTransform.settled(fit)

        let coarse = StitchDrawPlan.coarse(of: list, budget: budget)
        #expect(coarse != StitchDrawPlan.entire(of: list), "otherwise the rows below prove nothing")

        // Live, whatever the caller says about compositing: a live transform can never
        // composite a raster baked at another one, so the liveness guard comes first.
        #expect(StitchDrawPlan.forFrame(
            of: list, at: live, compositingRaster: false, budget: budget
        ) == coarse)
        #expect(StitchDrawPlan.forFrame(
            of: list, at: live, compositingRaster: true, budget: budget
        ) == coarse)

        // Settled with no usable raster is *not* a gesture: it draws everything, uncoarsened.
        #expect(StitchDrawPlan.forFrame(
            of: list, at: settled, compositingRaster: false, budget: budget
        ) == StitchDrawPlan.entire(of: list))

        // Settled over a valid raster draws only the live tail.
        #expect(StitchDrawPlan.forFrame(
            of: list, at: settled, compositingRaster: true, budget: budget
        ) == StitchDrawPlan.live(of: list))
    }

    // MARK: - T10 · ADR-009's batching claim, in the coarse plan too

    /// ADR-009's claim is about the *number of paths*, and coarsening must not buy its saving
    /// by emitting a stroke per span. Above the budget, or this is the existing `.entire`
    /// assertion again (`coarse == entire` there).
    @Test("the coarse plan keeps at most two strokes and one dot path per colour run")
    func theCoarsePlanKeepsAtMostTwoStrokesPerColourRun() {
        let list = SyntheticDesign.displayList(count: 50000, colorRuns: 5)
        let plan = StitchDrawPlan.coarse(of: list, budget: 4000)

        #expect(plan.strokes.count <= 2 * list.colorRuns.count)
        #expect(plan.dots.count == list.colorRuns.count)
        #expect(plan.strokes.count < list.count, "one path per span is the anti-goal")
    }

    // MARK: - T11 · the shipping samples are untouched

    /// **What makes the constant itself part of the contract.** Both shipping designs are below
    /// `liveStitchBudget`, so every frame they draw — settled, live or mid-gesture — is exactly
    /// the plan they drew before this story. Iterating `SampleLibrary.all` rather than `.first`
    /// is deliberate: the existing plan suite uses `.first` and therefore covers only the
    /// 3 194-stitch rosette, leaving the 2 976-stitch coil unasserted (US-310, P13).
    @Test("no shipping sample is coarsened at the default budget")
    func noShippingSampleIsCoarsenedAtTheDefaultBudget() throws {
        try #require(!SampleLibrary.all.isEmpty)

        for sample in SampleLibrary.all {
            var list = StitchDisplayList()
            var running = interpreter(sample.program)
            for events in tickBatches(&running) {
                list.append(contentsOf: RunBatch.reducing(events).stitches)
            }

            try #require(list.count > 1, "\(sample.id) must actually stitch")
            #expect(
                list.count < StitchDrawPlan.liveStitchBudget,
                "\(sample.id) has \(list.count) stitches, at or above the budget"
            )
            #expect(
                StitchDrawPlan.coarse(of: list, budget: StitchDrawPlan.liveStitchBudget)
                    == StitchDrawPlan.entire(of: list)
            )
        }
    }
}
