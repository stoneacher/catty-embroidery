import EmbroideryEngine
import StagePreview
import Testing

/// US-305: the dot/thread geometry ported from Catroid's `BrickValues.STITCH_SIZE`,
/// and the two ways this story deliberately refuses to derive it.
@Suite("Stitch draw metrics")
struct StitchDrawMetricsTests {
    /// The provenance, made checkable instead of left in a comment.
    ///
    /// `STITCH_SIZE = 3.15` is a *device-pixel* constant on the Catroid side
    /// (`BrickValues.java:187`), converted into virtual-stage units by `screenRatio`
    /// (`EmbroideryActor.kt:39`). Because `DSTFileConstants.java:56` pins Catroid's
    /// `STITCH_POINT_UNIT_FACTOR = 2f` — the same factor ADR-007 pins for our stage
    /// — one Catroid virtual unit *is* one stage point, so at the ordinary ratio ≈ 1
    /// the ported value is 3.15 stage points, and that is 0.63 mm of fabric.
    ///
    /// This test is what stops the number drifting into "3.15 view points" or "3.15
    /// millimetres" later: both would compile and neither would be Catroid's stitch.
    @Test("the ported stitch size is six hundred thirty micrometres of fabric")
    func theStitchSizeIsSixHundredThirtyMicrometresOfFabric() {
        let millimetres = StitchDrawMetrics.stitchSizeInStagePoints
            * StageGeometry.millimetresPerPoint

        #expect(millimetres.isApproximately(0.63))
    }

    /// The deviation from Catty, which derives its width from the **device**
    /// diagonal and the project's virtual size once at stream init
    /// (`EmbroideryStream.swift:54-66`) and therefore cannot respond to zoom at all.
    /// Ours is a function of the transform, so zooming in thickens the thread
    /// exactly as much as it enlarges the design.
    @Test("thread width and dot radius scale with the transform")
    func threadWidthAndDotRadiusScaleWithTheTransform() {
        #expect(StitchDrawMetrics.threadWidth(atScale: 1).isApproximately(3.15))
        #expect(StitchDrawMetrics.threadWidth(atScale: 2).isApproximately(6.3))
        #expect(StitchDrawMetrics.dotRadius(atScale: 2).isApproximately(6.3))
    }

    /// Catroid's rule, and the consequence that must not be "fixed": the *same*
    /// scalar is handed to `circle` as a **radius** and to `rectLine` as a **width**
    /// (`EmbroideryActor.kt:83, 88-94`), so a dot's diameter is twice the thread's
    /// width. That beading is what makes penetration points read as points.
    ///
    /// Catty is the counter-example and is not followed: it keeps a separate
    /// `stitchingCircleRadius = 3.0` (`SpriteKitDefines.swift:49`), so "the same
    /// value" is Catroid's rule alone.
    @Test("the dot radius equals the thread width, so a dot is twice as wide")
    func theDotRadiusEqualsTheThreadWidthAndSoReadsTwiceAsWide() {
        for scale in [0.5, 1.0, 4.0, 20.0] {
            #expect(
                StitchDrawMetrics.dotRadius(atScale: scale)
                    == StitchDrawMetrics.threadWidth(atScale: scale)
            )
        }
    }

    /// At `StageTransform.minimumScale` the unfloored width is 3.15 × 0.05 ≈ 0.16 pt
    /// — sub-pixel, i.e. a design that has zoomed itself into invisibility. The
    /// floor is a *legibility* decision about chrome, not a claim about the design's
    /// physical size, and it is stated here so nobody reads the scaling test above
    /// as unconditional.
    @Test("the width never falls below the visible floor, even at minimum zoom")
    func theWidthNeverFallsBelowTheVisibleFloorAtMinimumZoom() {
        let floored = StitchDrawMetrics.threadWidth(atScale: StageTransform.minimumScale)

        #expect(floored == StitchDrawMetrics.minimumWidthInViewPoints)
        #expect(StitchDrawMetrics.stitchSizeInStagePoints * StageTransform.minimumScale < floored)
    }

    /// A traversal is **chrome, not design data** — the machine trims travel, so it
    /// is not thread — which is why its width is a constant in view space rather
    /// than a function of the scale. A travel hint that grew with zoom would become
    /// a ribbon competing with the stitches it is meant to be subordinate to.
    @Test("the traversal hairline is constant in view space, not scaled")
    func theTraversalHairlineIsConstantInViewSpace() {
        #expect(StitchDrawMetrics.traversalWidthInViewPoints == 1)
        // Deliberately narrower than the thread it deviates from at every ordinary
        // zoom, so "hairline" is a property rather than an intention.
        #expect(
            StitchDrawMetrics.traversalWidthInViewPoints < StitchDrawMetrics.threadWidth(atScale: 1)
        )
    }
}

private extension Double {
    /// Floating-point comparison with a tolerance, so the tests state a physical
    /// quantity rather than a bit pattern: 3.15 × 0.2 is not exactly 0.63 in binary.
    func isApproximately(_ other: Double, within tolerance: Double = 1e-12) -> Bool {
        Swift.abs(self - other) <= tolerance
    }
}
