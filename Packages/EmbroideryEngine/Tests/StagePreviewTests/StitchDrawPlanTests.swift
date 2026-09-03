import EmbroideryEngine
import Samples
import StagePreview
import Testing

/// US-305 items 2, 3 and 7: the batching ADR-009 exists to require, the styles it
/// must actually carry, and the dot rule.
///
/// Asserted on `StitchDrawPlan` rather than through a recording renderer double —
/// see the story's test-plan correction. A double conforming to
/// `StagePreviewRenderer` records that protocol's *inputs*, so it never has a path
/// list to inspect; the plan is the value that makes these items assertable at all,
/// and it keeps them on the fast gate.
@Suite("Stitch draw plan")
struct StitchDrawPlanTests {
    /// Red · red · red · green · green — the story's "two-colour sample with only
    /// ordinary short moves". Axis-aligned and small on purpose: the distances are
    /// then unambiguous whatever measure `distanceInUnits` uses, and ADR-020 cannot
    /// reject any of them.
    private static let twoShortRuns = displayList([
        previewStitch(0, 0, PreviewColor.red),
        previewStitch(10, 0, PreviewColor.red),
        previewStitch(20, 0, PreviewColor.red),
        previewStitch(30, 0, PreviewColor.green),
        previewStitch(40, 0, PreviewColor.green)
    ])

    /// The same shape with one long hop inside the **first** run, so that run
    /// genuinely contains short → long → short and cannot be drawn by a single
    /// stroked path at one width.
    private static let firstRunWithALongGap = displayList([
        previewStitch(0, 0, PreviewColor.red),
        previewStitch(10, 0, PreviewColor.red),
        previewStitch(200, 0, PreviewColor.red),
        previewStitch(210, 0, PreviewColor.red),
        previewStitch(220, 0, PreviewColor.green),
        previewStitch(230, 0, PreviewColor.green)
    ])

    @Test("two colour runs of short moves yield exactly two thread paths")
    func twoColourRunsOfShortMovesYieldTwoThreadPaths() {
        let plan = StitchDrawPlan.entire(of: Self.twoShortRuns)

        #expect(plan.strokes.count == 2)
        #expect(plan.strokes.allSatisfy { $0.style == .thread })
        #expect(plan.strokes.map(\.color) == [PreviewColor.red, PreviewColor.green])
    }

    @Test("a long gap inside a run splits it into a thread path and a traversal path")
    func aLongGapInsideARunSplitsItIntoAThreadPathAndATraversalPath() {
        let plan = StitchDrawPlan.entire(of: Self.firstRunWithALongGap)

        // Three, per the story: red traversal, red thread, green thread.
        #expect(plan.strokes.count == 3)
        #expect(plan.strokes.filter { $0.style == .traversal }.count == 1)
        #expect(plan.strokes.filter { $0.style == .thread }.count == 2)
    }

    /// Item 3 — the item that stops an implementation classifying correctly and
    /// then stroking everything as ordinary thread. Nothing weaker than the exact
    /// member indices catches that.
    @Test("every stroke carries its style and its member indices")
    func everyStrokeCarriesItsStyleAndItsMemberIndices() {
        let plan = StitchDrawPlan.entire(of: Self.firstRunWithALongGap)

        // Segment i spans stitch i → i + 1. Of the five segments: 0 and 2 are
        // ordinary red thread, 1 is the long red hop, 3 crosses red → green and is
        // suppressed, 4 is ordinary green thread.
        //
        // Three flat `map`s rather than one `map` to a tuple: the tuple version made
        // the compiler give up ("unable to type-check this expression in reasonable
        // time") on the `contains` closures that compared all three members at once.
        // These are also strictly stronger, since they pin the order as well.
        #expect(plan.strokes.map(\.style) == [.traversal, .thread, .thread])
        #expect(plan.strokes.map(\.color) == [PreviewColor.red, PreviewColor.red, PreviewColor.green])
        // Pairs since US-310: `[[1→2], [0→1, 2→3], [4→5]]`, the same five segments the
        // implicit `i → i + 1` spelling described.
        #expect(plan.strokes.map { $0.segments.map(\.from) } == [[1], [0, 2], [4]])
        #expect(plan.strokes.allSatisfy { $0.segments.allSatisfy { $0.to == $0.from + 1 } })
    }

    /// Item 6's count assertion, which is what makes `.suppressed` observable at
    /// the plan level: N stitches give N − 1 segments, and one suppressed boundary
    /// must leave exactly N − 2 drawn. A planner that ignored `.suppressed` draws
    /// N − 1; one with the precedence backwards also draws N − 1.
    @Test("the suppressed boundary leaves exactly N minus two segments drawn")
    func theSuppressedBoundaryLeavesNMinusTwoDrawnSegments() {
        let list = Self.twoShortRuns
        let plan = StitchDrawPlan.entire(of: list)

        let drawn = plan.strokes.reduce(0) { $0 + $1.segments.count }

        #expect(drawn == list.count - 2)
    }

    @Test("no stroke is empty and none carries the suppressed style")
    func noStrokeIsEmptyAndNoneCarriesTheSuppressedStyle() {
        for list in [Self.twoShortRuns, Self.firstRunWithALongGap] {
            let plan = StitchDrawPlan.entire(of: list)

            #expect(plan.strokes.allSatisfy { !$0.segments.isEmpty })
            #expect(plan.strokes.allSatisfy { $0.style != .suppressed })
        }
    }

    @Test("a run whose only segments are traversals emits no thread path")
    func aRunWhoseOnlySegmentsAreTraversalsEmitsNoThreadPath() {
        let plan = StitchDrawPlan.entire(of: displayList([
            previewStitch(0, 0, PreviewColor.red),
            previewStitch(200, 0, PreviewColor.red),
            previewStitch(400, 0, PreviewColor.red)
        ]))

        #expect(plan.strokes.count == 1)
        #expect(plan.strokes.first?.style == .traversal)
        #expect(plan.strokes.first?.segments.map(\.from) == [0, 1])
    }

    /// Item 7. The dot rule is stated in display-list terms because Catroid's
    /// cannot be evaluated here: `isConnectingPoint` reads flags that live on
    /// assembled `Stitch` values, and the display list has no synthetic entries to
    /// exclude. **Every entry is a stitch the program requested, so every entry
    /// gets a dot** — including both endpoints of a traversal, which is exactly
    /// where Catroid's record-model rule would have skipped one.
    @Test("every display-list entry is dotted, including both traversal endpoints")
    func everyDisplayListEntryIsDotted() {
        for list in [Self.twoShortRuns, Self.firstRunWithALongGap] {
            let plan = StitchDrawPlan.entire(of: list)

            let dotted = plan.dots.reduce(0) { $0 + $1.count }
            #expect(dotted == list.count)

            // A gapless partition of the indices, in order — the same property
            // `StitchDisplayList` guarantees for its runs, carried through.
            #expect(plan.dots.map(\.indices.lowerBound) == plan.dots.map(\.indices.lowerBound).sorted())
            #expect(plan.dots.first?.indices.lowerBound == 0)
            #expect(plan.dots.last?.indices.upperBound == list.count)
        }
    }

    /// The z-order deviation from Catroid, pinned so it cannot be "simplified"
    /// back into stitch order. Catroid interleaves circle and line per point
    /// (`EmbroideryActor.kt:66-74`), which lets a later colour run paint over an
    /// earlier run's penetration dots; ours emits every stroke first and every dot
    /// after, and traversals sit under thread within a run.
    @Test("strokes are ordered by colour run with traversals under thread, and dots last")
    func strokesAreOrderedByColourRunAndTraversalsSitUnderThread() {
        let plan = StitchDrawPlan.entire(of: Self.firstRunWithALongGap)

        #expect(plan.strokes.map(\.style) == [.traversal, .thread, .thread])
        #expect(plan.strokes.map(\.color) == [PreviewColor.red, PreviewColor.red, PreviewColor.green])
    }

    @Test("a single-stitch design has one dot and no strokes")
    func aSingleStitchDesignHasOneDotAndNoStrokes() {
        let plan = StitchDrawPlan.entire(of: displayList([previewStitch(0, 0, PreviewColor.red)]))

        #expect(plan.strokes.isEmpty)
        #expect(plan.dots.map(\.indices) == [0 ..< 1])
    }

    @Test("an empty display list plans nothing")
    func anEmptyDisplayListPlansNothing() {
        let plan = StitchDrawPlan.entire(of: StitchDisplayList())

        #expect(plan.strokes.isEmpty)
        #expect(plan.dots.isEmpty)
    }

    /// ADR-009's batching claim, on real shipped content rather than a fixture:
    /// **never one shape per stitch**, which is the Catty anti-goal. The bound is
    /// at most two stroked paths plus one dot path per colour run.
    @Test("a real sample yields at most two thread paths and one dot path per run")
    func aRealSampleYieldsAtMostTwoThreadPathsAndOneDotPathPerRun() throws {
        let sample = try #require(SampleLibrary.all.first)
        var list = StitchDisplayList()
        // Not `var interpreter = interpreter(...)`: the local would shadow the
        // fixture from its own declaration point and fail to compile.
        var running = interpreter(sample.program)
        for events in tickBatches(&running) {
            list.append(contentsOf: RunBatch.reducing(events).stitches)
        }

        try #require(list.count > 1, "the sample must actually stitch for this to mean anything")
        let plan = StitchDrawPlan.entire(of: list)

        #expect(plan.strokes.count <= 2 * list.colorRuns.count)
        #expect(plan.dots.count == list.colorRuns.count)
        #expect(plan.strokes.count < list.count, "one path per stitch is the anti-goal")
    }
}
