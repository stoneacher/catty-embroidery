import EmbroideryEngine
import StagePreview
import Testing

/// US-307 items 1 and 2: the zoom state itself — what "follow the fit" means, and that a
/// finished gesture folds in exactly once.
///
/// **Item 1 as the story words it is already green.** `StageTransformTests
/// .pinchKeepsTheAnchorFixed` has pinched by 2.0 about a view point and asserted the
/// anchor's stage point since US-302, over four factors; the story's own prose concedes as
/// much ("US-302 delivers the math and its tests"). Re-asserting it here would be a test
/// that has never been red. What is new — and what the defect actually lives in — is that
/// SwiftUI's gesture values are **cumulative from the gesture's start**, so the anchor has
/// to survive being folded in against a baseline that did not move while the fingers did.
@Suite("Stage zoom")
struct StageZoomTests {
    private static let viewport = ViewSize(width: 390, height: 500)

    private static var fit: StageTransform {
        StageTransform.fitting(StageGeometry.box, in: viewport)
    }

    private static func expectClose(
        _ actual: StagePoint,
        _ expected: StagePoint,
        _ comment: Comment,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(abs(actual.x - expected.x) < 1e-9, comment, sourceLocation: sourceLocation)
        #expect(abs(actual.y - expected.y) < 1e-9, comment, sourceLocation: sourceLocation)
    }

    // MARK: - Following the fit

    @Test("a fresh zoom follows the fit and resolves to exactly it")
    func aFreshZoomFollowsTheFit() {
        let zoom = StageZoom()

        #expect(zoom.isFollowingFit)
        #expect(zoom.settled == nil)
        #expect(zoom.resolved(fitting: Self.fit) == Self.fit)
        #expect(zoom.magnification(fitting: Self.fit) == 1)
    }

    /// **The property that makes `nil` the right representation**, and the one a stored
    /// snapshot of the fitted transform would fail: while the stage follows the fit, a
    /// changed viewport changes what it resolves to. A rotation, an iPad resize, or a design
    /// growing outside the hoop mid-run all arrive as a different fit.
    @Test("following the fit means a changed viewport changes the resolved transform")
    func followingTheFitRefits() {
        let zoom = StageZoom()
        let narrow = StageTransform.fitting(StageGeometry.box, in: ViewSize(width: 200, height: 200))

        #expect(zoom.resolved(fitting: narrow) == narrow)
        #expect(zoom.resolved(fitting: narrow) != zoom.resolved(fitting: Self.fit))
    }

    /// The other half, and the half that stops a refit stealing the user's zoom: once a
    /// gesture has been committed, a new fit does **not** move the stage.
    @Test("an explicit transform survives a changed fit")
    func anExplicitTransformDoesNotRefit() {
        var zoom = StageZoom()
        zoom.commit(
            magnification: 3, anchor: ViewPoint(x: 100, y: 100), pan: .zero, fitting: Self.fit
        )
        let committed = zoom.resolved(fitting: Self.fit)
        let narrow = StageTransform.fitting(StageGeometry.box, in: ViewSize(width: 200, height: 200))

        #expect(zoom.resolved(fitting: narrow) == committed)
        #expect(!zoom.isFollowingFit)
    }

    @Test("fitting to content returns to following the fit")
    func fittingToContentReturnsToTheFit() {
        var zoom = StageZoom()
        zoom.commit(
            magnification: 4, anchor: ViewPoint(x: 10, y: 10), pan: .zero, fitting: Self.fit
        )
        #expect(!zoom.isFollowingFit)

        zoom.fitToContent()

        #expect(zoom.isFollowingFit)
        #expect(zoom.resolved(fitting: Self.fit) == Self.fit)
        // And it keeps following: a later fit is picked up, which a snapshot would not do.
        let narrow = StageTransform.fitting(StageGeometry.box, in: ViewSize(width: 200, height: 200))
        #expect(zoom.resolved(fitting: narrow) == narrow)
    }

    // MARK: - Committing a gesture

    /// The anchor invariance that is **this story's**, not US-302's: applied through the
    /// commit, against the baseline the transform still holds because nothing was written
    /// during the gesture.
    @Test("committing a pinch leaves the anchor's stage point fixed")
    func committingAPinchKeepsTheAnchorFixed() {
        let anchor = ViewPoint(x: 210, y: 130)
        for magnification in [0.5, 1.0, 2.0, 7.5] {
            var zoom = StageZoom()
            let anchored = Self.fit.stagePoint(of: anchor)

            zoom.commit(
                magnification: magnification, anchor: anchor, pan: .zero, fitting: Self.fit
            )

            Self.expectClose(
                zoom.resolved(fitting: Self.fit).stagePoint(of: anchor),
                anchored,
                "anchor fixed at magnification \(magnification)"
            )
        }
    }

    /// **A cumulative gesture must land where its final value says, not where the product of
    /// its callbacks says.** `MagnifyGesture.Value.magnification` is absolute since the
    /// gesture began, so an implementation that folded each callback in as a delta would
    /// reach 2 × 2 × 2 = 8 for a pinch whose callbacks read 2, then 2, then 2 — and the
    /// user's fingers only ever asked for 2. This is the defect the single-commit design
    /// exists to prevent, and it is invisible to a test that commits once.
    @Test("only the gesture's final cumulative value is applied, never the product")
    func onlyTheFinalCumulativeValueIsApplied() {
        let anchor = ViewPoint(x: 195, y: 250)
        var stepwise = StageZoom()
        for magnification in [1.4, 1.8, 2.0] {
            stepwise = StageZoom()
            stepwise.commit(
                magnification: magnification, anchor: anchor, pan: .zero, fitting: Self.fit
            )
        }

        var once = StageZoom()
        once.commit(magnification: 2.0, anchor: anchor, pan: .zero, fitting: Self.fit)

        #expect(stepwise == once)
        #expect(
            abs(stepwise.magnification(fitting: Self.fit) - 2) < 1e-9,
            "a cumulative 2× must be 2×, not 5.04×"
        )
    }

    @Test("committing a pan moves the stage by exactly the pan")
    func committingAPanMovesByExactlyThePan() {
        var zoom = StageZoom()
        let pan = ViewPoint(x: -40, y: 25)

        zoom.commit(magnification: 1, anchor: ViewPoint(x: 1, y: 2), pan: pan, fitting: Self.fit)

        let moved = zoom.resolved(fitting: Self.fit)
        #expect(moved.scale == Self.fit.scale)
        #expect(moved.translation.x == Self.fit.translation.x + pan.x)
        #expect(moved.translation.y == Self.fit.translation.y + pan.y)
    }

    /// **The order is pinned because it is observable and wrong the other way round.** The
    /// anchor is a view point measured in the gesture's start frame, so it names the stage
    /// point the user grabbed only before the pan is applied. Panning first anchors the zoom
    /// about whatever ends up under that coordinate — a visible jump on any gesture that
    /// both pinched and dragged, which is most of them.
    @Test("a pinch is applied before the pan, and the other order is different")
    func aPinchIsAppliedBeforeThePan() {
        let anchor = ViewPoint(x: 300, y: 120)
        let pan = ViewPoint(x: -60, y: 40)
        var zoom = StageZoom()

        zoom.commit(magnification: 2.5, anchor: anchor, pan: pan, fitting: Self.fit)

        let expected = Self.fit
            .pinched(by: 2.5, about: anchor, within: StageZoomBounds(fitting: Self.fit))
            .dragged(by: pan)
        #expect(zoom.resolved(fitting: Self.fit) == expected)

        let reversed = Self.fit
            .dragged(by: pan)
            .pinched(by: 2.5, about: anchor, within: StageZoomBounds(fitting: Self.fit))
        #expect(expected != reversed, "the two orders must differ or this pins nothing")
    }

    /// The clamp reaches the commit, and it is the *fit-aware* clamp: an out-of-hoop design
    /// pinched hard out comes back to its own fit rather than to the absolute 0.05.
    @Test("a committed pinch-out on an out-of-hoop design stops at that design's fit")
    func aCommittedPinchOutStopsAtTheDesignsFit() {
        let wide = StageTransform.fitting(
            StageBox(minX: -3201, minY: -20, maxX: 3201, maxY: 20),
            in: ViewSize(width: 288, height: 288)
        )
        #expect(wide.scale < StageTransform.minimumScale, "fixture premise")
        var zoom = StageZoom()

        zoom.commit(magnification: 1e-6, anchor: ViewPoint(x: 144, y: 144), pan: .zero, fitting: wide)

        #expect(zoom.resolved(fitting: wide).scale == wide.scale)
    }

    @Test("magnification is measured against the fit, so a fitted stage reads 1")
    func magnificationIsRelativeToTheFit() {
        var zoom = StageZoom()
        zoom.commit(
            magnification: 3, anchor: Self.viewport.center, pan: .zero, fitting: Self.fit
        )

        #expect(abs(zoom.magnification(fitting: Self.fit) - 3) < 1e-9)
        // Relative, not absolute: the same zoom against a different fit reads differently,
        // which is the whole reason the spoken value uses this rather than `scale`.
        let narrow = StageTransform.fitting(StageGeometry.box, in: ViewSize(width: 200, height: 200))
        #expect(zoom.magnification(fitting: narrow) != zoom.magnification(fitting: Self.fit))
    }
}
