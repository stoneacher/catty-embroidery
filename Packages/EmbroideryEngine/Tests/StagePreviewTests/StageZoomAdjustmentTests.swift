import StagePreview
import Testing

/// US-307 item 5 and criterion 7: zoom reachable **without gestures**, for VoiceOver and
/// Switch Control users who cannot pinch at all.
///
/// **None of these recomputes the step formula.** Asserting `scale == fit.scale * step`
/// would restate the implementation and stay green if the anchor were wrong, the clamp were
/// dropped, or the direction were inverted — the "expected value is computed rather than a
/// literal" shape this repo has now hit nine times. What is asserted instead are the
/// properties a user would notice: the centre does not drift, the two directions undo each
/// other, and both ends stop exactly at the bound rather than near it.
@Suite("Stage zoom adjustment")
struct StageZoomAdjustmentTests {
    private static let viewport = ViewSize(width: 390, height: 500)

    private static var fit: StageTransform {
        StageTransform.fitting(StageGeometry.box, in: viewport)
    }

    /// A documentation pin, deliberately the only literal in the suite. Criterion 9 obliges
    /// the close-out to record the step, so the number is fixed here rather than left free
    /// to drift away from what the ADR says.
    @Test("the adjustment step is the documented 1.5×")
    func theAdjustmentStepIsDocumented() {
        #expect(StageZoom.adjustmentStep == 1.5)
    }

    @Test("zooming in magnifies and zooming out reduces")
    func theDirectionsGoTheRightWay() {
        var zoomedIn = StageZoom()
        var zoomedOut = StageZoom()

        zoomedIn.adjust(.zoomIn, fitting: Self.fit, in: Self.viewport)
        zoomedOut.adjust(.zoomOut, fitting: Self.fit, in: Self.viewport)

        #expect(zoomedIn.magnification(fitting: Self.fit) > 1)
        #expect(zoomedOut.magnification(fitting: Self.fit) < 1)
    }

    /// **The anchoring property, differentially.** With no finger there is no anchor but the
    /// viewport's centre, and an implementation that anchored on the stage origin instead
    /// would walk a panned design off-screen — invisible to a scale assertion, obvious here.
    @Test("an adjustment leaves the stage point under the viewport centre fixed")
    func theViewportCentreIsFixed() {
        var zoom = StageZoom()
        // Start from a panned, zoomed stage, so origin-anchoring and centre-anchoring differ.
        zoom.commit(
            magnification: 2,
            anchor: ViewPoint(x: 40, y: 60),
            pan: ViewPoint(x: -75, y: 30),
            fitting: Self.fit
        )
        let centre = Self.viewport.center
        let before = zoom.resolved(fitting: Self.fit).stagePoint(of: centre)

        zoom.adjust(.zoomIn, fitting: Self.fit, in: Self.viewport)

        let after = zoom.resolved(fitting: Self.fit).stagePoint(of: centre)
        #expect(abs(after.x - before.x) < 1e-9)
        #expect(abs(after.y - before.y) < 1e-9)
    }

    /// Round-trip away from the clamps. This is what makes the step *reversible* for a user
    /// who overshoots — and it fails for an additive step, or for one whose two directions
    /// are not reciprocals.
    @Test("zooming in and back out returns to the same transform")
    func inAndOutRoundTrips() {
        var zoom = StageZoom()

        zoom.adjust(.zoomIn, fitting: Self.fit, in: Self.viewport)
        zoom.adjust(.zoomOut, fitting: Self.fit, in: Self.viewport)

        let resolved = zoom.resolved(fitting: Self.fit)
        #expect(abs(resolved.scale - Self.fit.scale) < 1e-9)
        #expect(abs(resolved.translation.x - Self.fit.translation.x) < 1e-9)
        #expect(abs(resolved.translation.y - Self.fit.translation.y) < 1e-9)
    }

    /// Stops **exactly** at the maximum, not near it and not past it. Bounded activation
    /// count, so a step that had stopped multiplying would hang this test rather than pass it.
    @Test("repeated zoom-in stops exactly at the maximum scale")
    func zoomInStopsAtTheMaximum() {
        var zoom = StageZoom()
        for _ in 0 ..< 40 {
            zoom.adjust(.zoomIn, fitting: Self.fit, in: Self.viewport)
        }

        #expect(zoom.resolved(fitting: Self.fit).scale == StageTransform.maximumScale)

        // And a further activation is a no-op rather than a drift.
        let atLimit = zoom
        zoom.adjust(.zoomIn, fitting: Self.fit, in: Self.viewport)
        #expect(zoom == atLimit)
    }

    @Test("repeated zoom-out stops exactly at the bound's floor")
    func zoomOutStopsAtTheFloor() {
        var zoom = StageZoom()
        for _ in 0 ..< 40 {
            zoom.adjust(.zoomOut, fitting: Self.fit, in: Self.viewport)
        }

        #expect(
            zoom.resolved(fitting: Self.fit).scale == StageZoomBounds(fitting: Self.fit).minimum
        )

        let atLimit = zoom
        zoom.adjust(.zoomOut, fitting: Self.fit, in: Self.viewport)
        #expect(zoom == atLimit)
    }

    /// The floor is the *fit-aware* one here too, so an assistive user on an out-of-hoop
    /// design can reach the whole design and not 11 % short of it.
    @Test("on an out-of-hoop design the floor is that design's own fit")
    func theFloorFollowsAnOutOfHoopFit() {
        let wide = StageTransform.fitting(
            StageBox(minX: -3201, minY: -20, maxX: 3201, maxY: 20),
            in: ViewSize(width: 288, height: 288)
        )
        #expect(wide.scale < StageTransform.minimumScale, "fixture premise")
        var zoom = StageZoom()

        for _ in 0 ..< 40 {
            zoom.adjust(.zoomOut, fitting: wide, in: ViewSize(width: 288, height: 288))
        }

        #expect(zoom.resolved(fitting: wide).scale == wide.scale)
    }

    /// An adjustment on a fitted stage must *stop* following the fit — otherwise the zoom it
    /// just applied would be discarded by the next refit, which is exactly the bug the
    /// `nil`-means-fit representation makes easy to write.
    @Test("adjusting a fitted stage makes its transform explicit")
    func adjustingMakesTheTransformExplicit() {
        var zoom = StageZoom()
        #expect(zoom.isFollowingFit)

        zoom.adjust(.zoomIn, fitting: Self.fit, in: Self.viewport)

        #expect(!zoom.isFollowingFit)
        let narrow = StageTransform.fitting(StageGeometry.box, in: ViewSize(width: 200, height: 200))
        #expect(
            zoom.resolved(fitting: narrow) == zoom.resolved(fitting: Self.fit),
            "a refit must not discard an adjustment"
        )
    }
}
