import EmbroideryEngine
import StagePreview
import Testing

/// What the coarse plan must **cover**, and what it must never **cross**.
///
/// Split from `StitchDrawPlanCoarseningTests` — which asserts the plan's other shape properties —
/// and from `StitchDrawPlanCoarseningRuleTests`, which asserts the arithmetic. The seam is the
/// one thing US-310 could get wrong in a way a user would see and a test would not: drawing
/// thread across a jump (ADR-024's named defect in *both* references) or, the mirror image,
/// failing to draw thread right up to one. Review found the second of those unasserted, so the
/// two now live together, since neither is safe without the other.
///
/// The file boundary itself is SwiftLint's 400-line limit under `--strict`, for the third time
/// in this story.
@Suite("Stitch draw plan coarsening coverage")
struct StitchDrawPlanCoarseningCoverageTests {
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

    /// Lists that exercise **both** ways an open span has to be closed — a traversal and a
    /// colour boundary — in the positions that are easy to get wrong: a hop in the middle of a
    /// run, a hop as a run's last interval, a run of length 1, and consecutive hops.
    private static let travelAndColourFixtures: [StitchDisplayList] = [
        twoShortRuns,
        firstRunWithALongGap,
        onlyTraversals,
        // Hop in the middle of the first run, then a colour change, then a hop that ends the run.
        displayList([
            previewStitch(0, 0, PreviewColor.red),
            previewStitch(10, 0, PreviewColor.red),
            previewStitch(20, 0, PreviewColor.red),
            previewStitch(400, 0, PreviewColor.red),
            previewStitch(410, 0, PreviewColor.red),
            previewStitch(420, 0, PreviewColor.green),
            previewStitch(430, 0, PreviewColor.green),
            previewStitch(900, 0, PreviewColor.green),
            previewStitch(910, 0, PreviewColor.blue)
        ]),
        // Two hops back to back, so a merged pair would be visible, plus a length-1 run.
        displayList([
            previewStitch(0, 0, PreviewColor.red),
            previewStitch(300, 0, PreviewColor.red),
            previewStitch(600, 0, PreviewColor.red),
            previewStitch(610, 0, PreviewColor.red),
            previewStitch(620, 0, PreviewColor.green),
            previewStitch(630, 0, PreviewColor.blue),
            previewStitch(640, 0, PreviewColor.blue)
        ]),
        // Twenty short moves either side of one hop — T5's shape, at a longer run length.
        hopInTheMiddle
    ]

    /// Built statement by statement rather than as one concatenated literal: the `+` chain of
    /// two `map`s and an array defeated the type-checker outright ("unable to type-check this
    /// expression in reasonable time"), the same hazard `StitchDrawPlanTests` records for a
    /// three-member tuple.
    private static let hopInTheMiddle: StitchDisplayList = {
        var stitches = (0 ..< 20).map { previewStitch(Double($0) * 10, 0, PreviewColor.red) }
        stitches.append(previewStitch(1_000, 0, PreviewColor.red))
        for index in 0 ..< 20 {
            stitches.append(previewStitch(1_000 + Double(index + 1) * 10, 0, PreviewColor.red))
        }
        return displayList(stitches)
    }()

    /// Lists whose interior holds a coordinate the renderer cannot draw. Codex's reproducer is
    /// the first; the others put the bad point first, last, adjacent to a colour change, and in
    /// pairs, since a span breaking on one of them must break on all.
    private static let nonFiniteFixtures: [StitchDisplayList] = [
        displayList([
            previewStitch(0, 0, PreviewColor.red),
            previewStitch(10, 0, PreviewColor.red),
            previewStitch(.nan, 0, PreviewColor.red),
            previewStitch(1_000, 0, PreviewColor.red),
            previewStitch(1_010, 0, PreviewColor.red),
            previewStitch(1_020, 0, PreviewColor.red),
            previewStitch(1_030, 0, PreviewColor.red)
        ]),
        displayList([
            previewStitch(.infinity, 0, PreviewColor.red),
            previewStitch(10, 0, PreviewColor.red),
            previewStitch(20, 0, PreviewColor.red),
            previewStitch(30, 0, PreviewColor.red)
        ]),
        displayList([
            previewStitch(0, 0, PreviewColor.red),
            previewStitch(10, 0, PreviewColor.red),
            previewStitch(20, 0, PreviewColor.red),
            previewStitch(0, .nan, PreviewColor.red)
        ]),
        displayList([
            previewStitch(0, 0, PreviewColor.red),
            previewStitch(.nan, .nan, PreviewColor.red),
            previewStitch(-.infinity, 0, PreviewColor.red),
            previewStitch(20, 0, PreviewColor.red),
            previewStitch(30, 0, PreviewColor.green),
            previewStitch(40, 0, PreviewColor.green),
            previewStitch(.nan, 0, PreviewColor.green),
            previewStitch(60, 0, PreviewColor.green)
        ]),
        // **Finite, and still unreachable** (`/codex-review` round 3): `1e307` is a perfectly
        // finite `Double` that `EmbroideryPoint(converting:)` rejects, and at
        // `StageTransform.maximumScale` it maps to a non-finite view point — so the renderer
        // skips both adjacent intervals while a span joined over it would be drawn. A
        // finiteness test passes this fixture; the reachability test does not.
        displayList([
            previewStitch(0, 0, PreviewColor.red),
            previewStitch(1e307, 0, PreviewColor.red),
            previewStitch(10, 0, PreviewColor.red),
            previewStitch(20, 0, PreviewColor.red),
            previewStitch(1e300, 1e300, PreviewColor.red),
            previewStitch(30, 0, PreviewColor.red)
        ])
    ]

    /// Whether the interval starting at `index` joins two stitches the machine can actually
    /// reach — the intervals a coarse plan is allowed to merge, and the ones the renderer draws.
    ///
    /// Uses `EmbroideryPoint(converting:)`, the same public predicate the planner and
    /// `EmbroideryStream.requiresTraversal` consult. **An earlier version repeated the planner's
    /// finiteness proxy instead**, which `/codex-review` round 3 pointed out is the test
    /// asserting the implementation against itself — and it was the weaker rule, so it could not
    /// have caught the `1e307`-at-maximum-scale case.
    private static func isDrawableInterval(_ index: Int, of list: StitchDisplayList) -> Bool {
        EmbroideryPoint(converting: list.stitches[index].position) != nil
            && EmbroideryPoint(converting: list.stitches[index + 1].position) != nil
    }

    private static func threadSegments(_ plan: StitchDrawPlan) -> [StitchDrawPlan.Segment] {
        plan.strokes.filter { $0.style == .thread }.flatMap(\.segments)
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

        let plan = StitchDrawPlan.coarse(of: list, threshold: 8, target: 8)

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

    /// **A coarse span must not step over a stitch the renderer cannot draw** (`/codex-review`
    /// round 1, finding 1).
    ///
    /// ADR-021 divergence #5 deliberately lets a coordinate the *stream* rejects into the display
    /// list, so a position can be non-finite. `EmbroideryStream.requiresTraversal` returns
    /// **false** when conversion rejects such a point — it cannot compute a distance — so
    /// `StitchSegmentStyle.classifying` calls both intervals touching it `.thread`. The fine plan
    /// emits them and the renderer then skips each one, because `segmentPath` guards every
    /// subpath on `isDrawable`: nothing is drawn there, which is right, since the machine's
    /// surviving state travels across that gap.
    ///
    /// A coarse span would instead *join over* the bad vertex, and its two endpoints are finite —
    /// so the renderer draws one solid line straight across the travel. That is the exact ADR-024
    /// defect this story must never reproduce, reachable only through coarsening.
    ///
    /// So the rule: **a span never joins across a non-finite vertex**; the intervals touching one
    /// are emitted individually, which keeps the coverage identical to the fine plan while
    /// leaving the renderer's per-subpath skip to do its job. Asserted on *interior* vertices
    /// only — a unit segment may legitimately end on a bad point, exactly as the fine plan's does.
    @Test("a coarse span never joins across a stitch the renderer cannot draw")
    func aCoarseSpanNeverJoinsAcrossANonFiniteStitch() {
        for list in Self.nonFiniteFixtures {
            for target in [1, 2, 3, 5, 97] {
                let plan = StitchDrawPlan.coarse(of: list, threshold: 0, target: target)

                for segment in Self.threadSegments(plan) where segment.to > segment.from + 1 {
                    for index in (segment.from + 1) ..< segment.to {
                        let position = list.stitches[index].position
                        #expect(
                            position.x.isFinite && position.y.isFinite,
                            "target \(target): segment \(segment.from)→\(segment.to) steps over \(index)"
                        )
                    }
                }

                // **The coverage matches the fine plan's *drawn* intervals, not its emitted
                // ones** (`/codex-review` round 2). An interval touching a non-finite vertex is
                // skipped by `segmentPath` in either plan, so the coarse plan does not carry it
                // at all — which is what keeps ADR-030's bound true even for a list that is
                // entirely non-finite.
                // **What the coarse plan must match depends on whether it is coarsening at all**
                // (`/codex-review` round 4). At stride 1 nothing merges, so it must match the fine
                // plan *exactly* — dropping an unreachable interval there would change `.entire`,
                // which ADR-021 forbids. Above stride 1 it matches the fine plan's **reachable**
                // intervals, because an interval it cannot merge across is one it drops.
                let fine = StitchDrawPlan.entire(of: list)
                let stride = StitchDrawPlan.coarseningStride(forStitchCount: list.count, target: target)
                let finelyThreaded = Self.threadSegments(fine).map(\.from)
                let expected = stride == 1
                    ? finelyThreaded
                    : finelyThreaded.filter { Self.isDrawableInterval($0, of: list) }
                let covered = Self.threadSegments(plan).flatMap { $0.from ..< $0.to }
                #expect(Set(covered) == Set(expected), "target \(target), stride \(stride)")
                #expect(covered.count == Set(covered).count)
            }
        }
    }

    /// **The assertion the story should have had from the start, and it took a review to find.**
    ///
    /// Every other test here checks that what *is* emitted is legitimate: thread segments span
    /// only thread intervals (T5), nothing crosses a run (T6), the chain has no gaps on a
    /// traversal-free fixture (T4). None of them checks that the coarse plan draws *everything*
    /// the fine plan draws — so dropping the span that is open when travel or a colour change
    /// arrives left all 750 tests green. On screen that is up to `stride − 1` stitch intervals of
    /// missing thread immediately before **every** jump and **every** colour swap: at the shipped
    /// stride of 51, a whole coarse segment of blank fabric at each, mid-gesture only.
    ///
    /// So this asserts **set equality of covered intervals**, which is one assertion that
    /// simultaneously rules out gaps, duplicates, thread across a jump and thread across a colour
    /// change — and it is the assertion ADR-030's "an open span is closed at travel and at a
    /// colour boundary rather than drawn through it" actually makes. The fixtures deliberately put
    /// a hop *inside* each colour run and end one run on a hop, so both close paths run.
    @Test("coarse thread covers exactly the intervals the fine plan threads")
    func coarseThreadCoversExactlyTheIntervalsTheFinePlanThreads() {
        for list in Self.travelAndColourFixtures {
            let fine = StitchDrawPlan.entire(of: list)
            let finelyThreaded = Set(Self.threadSegments(fine).map(\.from))

            for target in [1, 2, 3, 5, 8, 97] {
                let plan = StitchDrawPlan.coarse(of: list, threshold: 0, target: target)
                let covered = Self.threadSegments(plan).flatMap { $0.from ..< $0.to }

                #expect(
                    Set(covered) == finelyThreaded,
                    "target \(target): covered \(covered.sorted()) against \(finelyThreaded.sorted())"
                )
                // No interval is drawn twice — a `Set` comparison alone would not see that, and a
                // double-drawn traversal composites its alpha twice.
                #expect(covered.count == Set(covered).count, "target \(target): an interval repeats")

                // The traversals, likewise exactly and verbatim.
                let travelled = plan.strokes.filter { $0.style == .traversal }.flatMap(\.segments)
                #expect(
                    Set(travelled.map(\.from))
                        == Set(fine.strokes.filter { $0.style == .traversal }.flatMap(\.segments).map(\.from))
                )
                #expect(travelled.allSatisfy { $0.to == $0.from + 1 })
            }
        }
    }

    /// **The fine windows are untouched by any of this**, which is the claim `/codex-review`
    /// round 4 caught being false: the joinability guard was consulted at stride 1 too, so
    /// `.entire` silently stopped emitting intervals touching an unconvertible coordinate — and
    /// those are exactly the stitches ADR-021 says the display list must still show, since the
    /// *stream* rejecting a coordinate is not the same as the *renderer* being unable to draw it.
    /// A coordinate past `Int64.max / 2` is unconvertible and still maps finitely at a small
    /// scale.
    @Test("a fine plan emits every interval, reachable or not")
    func aFinePlanEmitsEveryIntervalReachableOrNot() {
        for list in Self.nonFiniteFixtures {
            let fine = StitchDrawPlan.entire(of: list)

            #expect(
                StitchDrawPlan.coarse(of: list, threshold: .max, target: .max) == fine,
                "an uncoarsened plan is the fine plan, guard or no guard"
            )

            // Stated the other way too: every interval the classifier calls thread is emitted.
            let threaded = (0 ..< Swift.max(0, list.count - 1)).filter { index in
                StitchSegmentStyle.classifying(
                    from: list.stitches[index], to: list.stitches[index + 1]
                ) == .thread
            }
            #expect(Set(Self.threadSegments(fine).map(\.from)) == Set(threaded))
        }
    }

    /// **Every break can cost a partial span, and the bound has to say so** (`/codex-review`
    /// round 3, finding 2). Dropping wholly unreachable intervals fixed the all-rejected case,
    /// but a list that alternates reachable and unreachable stitches breaks the span at every
    /// third interval, so it yields one short segment per island however large the stride is.
    ///
    /// The honest bound is therefore `ceil(count / stride)` plus one term per *thing that forces
    /// a break*: the colour runs, the traversals, and the unreachable intervals. Asserted here
    /// against a fixture built to maximise the last of those, which is the case the synthetic
    /// design (all finite) and the all-rejected fixture (no drawable islands) both miss.
    @Test("the bound holds when unreachable stitches break the spans")
    func theBoundHoldsWhenUnreachableStitchesBreakTheSpans() {
        var stitches: [PreviewStitch] = []
        for index in 0 ..< 1_666 {
            let base = Double(index) * 10
            stitches.append(previewStitch(base, 0, PreviewColor.red))
            stitches.append(previewStitch(base + 2, 0, PreviewColor.red))
            stitches.append(previewStitch(.nan, 0, PreviewColor.red))
        }
        let list = displayList(stitches)
        let target = 100
        let stride = StitchDrawPlan.coarseningStride(forStitchCount: list.count, target: target)

        let plan = StitchDrawPlan.coarse(of: list, threshold: 0, target: target)
        let fine = StitchDrawPlan.entire(of: list)

        let unreachable = (0 ..< list.count - 1).count { !Self.isDrawableInterval($0, of: list) }
        let traversals = fine.strokes.filter { $0.style == .traversal }.flatMap(\.segments).count
        let bound = (list.count + stride - 1) / stride + list.colorRuns.count + traversals + unreachable

        #expect(Self.threadSegments(plan).count <= bound)
        // Two-sided: the drawable islands must still be drawn, one segment each.
        #expect(Self.threadSegments(plan).count >= 1_000)
        #expect(stride > 1, "otherwise this says nothing about coarsening")
    }

    /// **The bound has to survive the input ADR-021 permits, and the first fix did not**
    /// (`/codex-review` round 2, finding 1). A design whose coordinates are all rejected has
    /// *every* interval unjoinable; emitting each one individually — the shape of round 1's fix —
    /// produced 49 999 segments for a plan whose stated bound is about 1 001, i.e. it defeated
    /// coarsening exactly where coarsening is needed. Omitting them costs nothing on screen,
    /// because the renderer already skipped every one.
    @Test("a design of rejected coordinates plans nothing to stroke")
    func aDesignOfRejectedCoordinatesPlansNothingToStroke() {
        var stitches: [PreviewStitch] = []
        for index in 0 ..< 5_000 {
            stitches.append(PreviewStitch(
                position: StagePoint(x: index.isMultiple(of: 2) ? .nan : .infinity, y: 0),
                color: PreviewColor.red
            ))
        }
        let list = displayList(stitches)

        let plan = StitchDrawPlan.coarse(of: list, threshold: 0, target: 100)

        #expect(Self.threadSegments(plan).isEmpty)
        #expect(plan.strokes.allSatisfy { $0.style != .thread })
        // The dots are unaffected: they are per-index, and the renderer skips an undrawable
        // centre one dot at a time, so nothing here is the plan's business.
        #expect(plan.dots.count == 1)
    }

}
