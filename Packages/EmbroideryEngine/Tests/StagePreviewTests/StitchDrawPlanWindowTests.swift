import EmbroideryEngine
import StagePreview
import Testing

/// US-305 item 5: the settled/live split ADR-009 rests on.
///
/// **The story's own formulation of this item was off by one and is corrected
/// here.** It asked that "after `markSettled(upTo: k)`, the per-frame drawn set is
/// exactly `stitches[k...]`". That is true of the **dots** and false of the
/// **segments**: the watermark splits stitches, but a segment joins *two* of them,
/// so segment `(k−1, k)` straddles it and belongs to neither window under the
/// literal reading. An implementation satisfying the item as written renders a
/// permanent one-segment gap at every watermark advance.
///
/// So the rule is: the bake draws strictly inside its window, the live pass starts
/// one index earlier — and what is asserted is the **partition**, which is both
/// honest and strictly stronger than the original.
@Suite("Stitch draw plan windows")
struct StitchDrawPlanWindowTests {
    /// Five stitches in one colour, all ordinary short moves, so every one of the
    /// four segments is `.thread` and the windowing is the only variable.
    private static func oneRun(settledUpTo settled: Int) -> StitchDisplayList {
        var list = displayList([
            previewStitch(0, 0, PreviewColor.red),
            previewStitch(10, 0, PreviewColor.red),
            previewStitch(20, 0, PreviewColor.red),
            previewStitch(30, 0, PreviewColor.red),
            previewStitch(40, 0, PreviewColor.red)
        ])
        list.markSettled(upTo: settled)
        return list
    }

    /// Every segment start in a plan, flattened and sorted — the plan's coverage,
    /// independent of how it happened to group the segments into strokes.
    ///
    /// Reads `from` off each `Segment` since US-310, where a drawn segment became an explicit
    /// index *pair*. In these windows that loses nothing: every segment here spans one stitch
    /// interval, which is what `everySegmentInAFineWindowSpansOneStitchInterval` pins.
    private static func segmentStarts(_ plan: StitchDrawPlan) -> [Int] {
        plan.strokes.flatMap(\.segments).map(\.from).sorted()
    }

    private static func dottedIndices(_ plan: StitchDrawPlan) -> [Int] {
        plan.dots.flatMap { Array($0.dottedIndices) }.sorted()
    }

    /// **The invariant US-310 must not break while it makes segments coarsenable.** The three
    /// windows here are the *fine* ones: whatever the coarse path does, `.entire`, `.settled`
    /// and `.live` still draw one segment per stitch interval, so every index the renderer
    /// reads is `from` and `from + 1` as it always was. Without this, a stride leaking into a
    /// fine window would leave every assertion in this suite still green — they all read
    /// `from` — while the thread rendered in dashes.
    @Test("every segment in a fine window spans exactly one stitch interval")
    func everySegmentInAFineWindowSpansOneStitchInterval() {
        let list = Self.oneRun(settledUpTo: 2)

        for plan in [StitchDrawPlan.entire(of: list), .settled(of: list), .live(of: list)] {
            for segment in plan.strokes.flatMap(\.segments) {
                #expect(segment.to == segment.from + 1)
            }
        }
    }

    @Test("the live plan dots are exactly the stitches after the watermark")
    func theLivePlanDotsAreExactlyTheStitchesAfterTheWatermark() {
        let list = Self.oneRun(settledUpTo: 2)

        #expect(Self.dottedIndices(.live(of: list)) == [2, 3, 4])
        #expect(Self.dottedIndices(.settled(of: list)) == [0, 1])
    }

    /// The discovery this suite exists for: without this, the thread shows a gap at
    /// the watermark that no other test in the story would catch.
    @Test("the live plan includes the segment entering the watermark")
    func theLivePlanIncludesTheSegmentEnteringTheWatermark() {
        let list = Self.oneRun(settledUpTo: 2)

        // Segment 1 spans stitch 1 → 2 and therefore straddles a watermark of 2.
        // It is the live pass's, because stitch 1 is settled and cannot change
        // while stitch 2 still can.
        #expect(Self.segmentStarts(.live(of: list)).contains(1))
        #expect(Self.segmentStarts(.settled(of: list)) == [0])
    }

    @Test("the settled and live plans partition the whole plan, disjointly")
    func theSettledAndLivePlansPartitionTheWholePlan() {
        for settled in 0 ... 5 {
            let list = Self.oneRun(settledUpTo: settled)
            let entire = StitchDrawPlan.entire(of: list)
            let settledPlan = StitchDrawPlan.settled(of: list)
            let livePlan = StitchDrawPlan.live(of: list)

            let covered = (Self.segmentStarts(settledPlan) + Self.segmentStarts(livePlan)).sorted()
            #expect(
                covered == Self.segmentStarts(entire),
                "segments must be covered exactly once at watermark \(settled)"
            )

            let dotted = (Self.dottedIndices(settledPlan) + Self.dottedIndices(livePlan)).sorted()
            #expect(
                dotted == Self.dottedIndices(entire),
                "dots must be covered exactly once at watermark \(settled)"
            )
        }
    }

    @Test("a watermark at the full count leaves nothing live")
    func markSettledAtTheCountLeavesNothingLive() {
        let list = Self.oneRun(settledUpTo: 5)
        let live = StitchDrawPlan.live(of: list)

        #expect(live.dots.isEmpty)
        // The last segment is inside the settled window once every stitch is
        // settled, so there is no bridging segment left to hand over.
        #expect(live.strokes.isEmpty)
        #expect(Self.segmentStarts(.settled(of: list)) == [0, 1, 2, 3])
    }

    @Test("a watermark at zero leaves everything live")
    func markSettledAtZeroLeavesEverythingLive() {
        let list = Self.oneRun(settledUpTo: 0)

        #expect(StitchDrawPlan.settled(of: list).strokes.isEmpty)
        #expect(StitchDrawPlan.settled(of: list).dots.isEmpty)
        #expect(StitchDrawPlan.live(of: list) == StitchDrawPlan.entire(of: list))
    }

    /// A colour-run boundary sitting exactly on the watermark: the suppressed
    /// segment must not reappear in either window, and the two windows must still
    /// partition. The interaction of the two rules is where an off-by-one would
    /// hide.
    @Test("a suppressed boundary at the watermark stays undrawn in both windows")
    func aSuppressedBoundaryAtTheWatermarkStaysUndrawnInBothWindows() {
        var list = displayList([
            previewStitch(0, 0, PreviewColor.red),
            previewStitch(10, 0, PreviewColor.red),
            previewStitch(20, 0, PreviewColor.green),
            previewStitch(30, 0, PreviewColor.green)
        ])
        list.markSettled(upTo: 2)

        let covered = (
            Self.segmentStarts(.settled(of: list)) + Self.segmentStarts(.live(of: list))
        ).sorted()

        // Segments 0 and 2 are drawn; segment 1 crosses red → green and is not.
        #expect(covered == [0, 2])
    }
}
