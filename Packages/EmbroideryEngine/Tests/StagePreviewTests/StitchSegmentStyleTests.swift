import EmbroideryEngine
import StagePreview
import Testing

/// US-305 item 6: the four-case classification, its load-bearing precedence, and
/// the two cases found by reading the trigger at its source.
///
/// Pure and pair-wise, so it runs under `swift test` with no simulator — which is
/// the whole reason the classification lives in `StagePreview` and not in the
/// renderer (see the story's test-plan correction).
@Suite("Stitch segment classification")
struct StitchSegmentStyleTests {
    @Test("an ordinary short move is drawn as thread")
    func anOrdinaryShortMoveIsThread() {
        let style = StitchSegmentStyle.classifying(
            from: previewStitch(0, 0, PreviewColor.red),
            to: previewStitch(10, 0, PreviewColor.red)
        )

        #expect(style == .thread)
    }

    @Test("a move past the encodable delta is drawn as traversal")
    func aMovePastTheEncodableDeltaIsTraversal() {
        // 61 stage points = 122 units, one past `DSTStitchRecord.maxDelta`, so
        // the stream would interpolate this as machine travel.
        let style = StitchSegmentStyle.classifying(
            from: previewStitch(0, 0, PreviewColor.red),
            to: previewStitch(61, 0, PreviewColor.red)
        )

        #expect(style == .traversal)
    }

    /// **ADR-019: this golden sits exactly on the threshold, so it states the
    /// comparison it depends on.**
    ///
    /// 60.5 stage points is 121 units, and `DSTStitchRecord.maxDelta = 121` is an
    /// *inclusive* bound — one record encodes it, so no travel is needed.
    /// `interpolationSplitCount` reaches that conclusion through a strict `>` on
    /// **both** of its clauses (the rounded difference and the round-then-subtract
    /// encoded delta), and this pair is 121 by both measures: from the origin the
    /// conversion is exact, and more generally `round(d) == 121` forces
    /// `d < 121.5`, which bounds the encoded delta at 121 as well — so the two
    /// clauses cannot disagree *at this boundary*, whatever they do further out.
    ///
    /// Loosening either comparison to `>=` reclassifies every 121-unit move as
    /// travel and fails here loudly, which is the point of pinning it.
    @Test("exactly one hundred twenty-one units is still thread, not traversal")
    func exactlyOneHundredTwentyOneUnitsIsStillThread() {
        let style = StitchSegmentStyle.classifying(
            from: previewStitch(0, 0, PreviewColor.red),
            to: previewStitch(60.5, 0, PreviewColor.red)
        )

        #expect(style == .thread)
    }

    @Test("a colour-run boundary draws no segment at all")
    func aColourRunBoundaryIsSuppressed() {
        let style = StitchSegmentStyle.classifying(
            from: previewStitch(0, 0, PreviewColor.red),
            to: previewStitch(10, 0, PreviewColor.green)
        )

        #expect(style == .suppressed)
    }

    /// The precedence case, and the reason the cases are *ordered* rather than
    /// merely listed: a thread swap and a long move can coincide, and drawing a
    /// travel line there would imply the machine travelled between two colours it
    /// actually stopped between.
    @Test("a boundary that is also a long gap is suppressed, not traversal")
    func aBoundaryThatIsAlsoALongGapIsSuppressedNotTraversal() {
        let style = StitchSegmentStyle.classifying(
            from: previewStitch(0, 0, PreviewColor.red),
            to: previewStitch(200, 0, PreviewColor.green)
        )

        #expect(style == .suppressed, "the colour-run boundary must win over the traversal")
    }

    /// ADR-021 divergence #5, surfacing in the renderer.
    ///
    /// `requiresTraversal` answers "would the stream interpolate this as travel",
    /// and for a move the stream **refuses outright** the answer is no — so the
    /// preview draws ordinary thread across a move the machine will not make at
    /// all. Pinned rather than left to be found, because the obvious reading of
    /// "unstitchable" is that it should look like travel, and it does not.
    @Test("an unstitchable move is drawn as thread, not traversal")
    func anUnstitchableMoveIsDrawnAsThreadNotTraversal() {
        let style = StitchSegmentStyle.classifying(
            from: previewStitch(0, 0, PreviewColor.red),
            to: previewStitch(1e300, 0, PreviewColor.red)
        )

        #expect(style == .thread)
    }

    /// The equivalence the planner rests on, checked differentially rather than
    /// believed: "the colours differ" and "the display list opened a new run" are
    /// the same predicate, because `StitchDisplayList.append` opens a run exactly
    /// when consecutive colours differ. Same pattern as `requiresTraversal`'s own
    /// doc comment, which checks its stream-state assumption instead of asserting
    /// it.
    @Test("colour inequality agrees with the display list's own run boundaries")
    func colourInequalityAgreesWithTheDisplayListsRunBoundaries() {
        let list = displayList([
            previewStitch(0, 0, PreviewColor.red),
            previewStitch(10, 0, PreviewColor.red),
            previewStitch(20, 0, PreviewColor.green),
            previewStitch(30, 0, PreviewColor.blue),
            previewStitch(40, 0, PreviewColor.blue)
        ])

        // Every index that starts a run, as the list itself reports them.
        let runStarts = Set(list.colorRuns.map(\.range.lowerBound))
        // Every index whose incoming segment the classifier suppresses.
        let suppressed = Set(
            (1 ..< list.count).filter {
                StitchSegmentStyle.classifying(
                    from: list.stitches[$0 - 1], to: list.stitches[$0]
                ) == .suppressed
            }
        )

        // The first run starts at 0 and has no incoming segment, so it is the one
        // run start with nothing to suppress.
        #expect(suppressed == runStarts.subtracting([0]))
    }
}
