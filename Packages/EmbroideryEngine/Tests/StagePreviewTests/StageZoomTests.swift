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

    /// **`commit` compounds, which is why the caller must call it once per gesture.**
    ///
    /// This replaces a test that could not fail. The original meant to assert "only the
    /// gesture's final cumulative value is applied, never the product", looped over 1.4, 1.8
    /// and 2.0 — and re-created the subject *inside* the loop, so the whole loop was the
    /// single commit it compared against and the assertion reduced to `once == once`
    /// (`swift-code-reviewer`; deleting that one line makes it fail at 5.04×, exactly the
    /// number its own comment predicted).
    ///
    /// It could not be repaired in place, because the property it named is not this type's.
    /// `commit` is *supposed* to compound — that is what folding a gesture into a transform
    /// means — and "applied exactly once" is a fact about how many times the **view** calls
    /// it, which no package test can observe. So what is pinned here is the contract the view
    /// relies on, written as the thing that breaks if the view ever commits per callback; the
    /// view's half is measured on the simulator instead.
    @Test("commit compounds, so a gesture must be committed exactly once")
    func committingTwiceCompounds() {
        let anchor = ViewPoint(x: 195, y: 250)
        var twice = StageZoom()

        twice.commit(magnification: 2, anchor: anchor, pan: .zero, fitting: Self.fit)
        twice.commit(magnification: 2, anchor: anchor, pan: .zero, fitting: Self.fit)

        #expect(abs(twice.magnification(fitting: Self.fit) - 4) < 1e-9)

        var once = StageZoom()
        once.commit(magnification: 2, anchor: anchor, pan: .zero, fitting: Self.fit)
        #expect(twice != once, "were these equal, committing per callback would be harmless")
    }
    /// **The mid-gesture frame and the committed transform are the same computation.**
    ///
    /// `previewing` is what the view draws each frame with while fingers are down, and
    /// `commit` is what it stores when they lift. If they could differ, the content would
    /// shift at release — which this story already shipped once, when a threshold subtraction
    /// applied to one and not the other. Asserted over a spread rather than one case, because
    /// the failure would be a small offset a single sample could miss.
    @Test("what a gesture previews is exactly what it commits")
    func previewMatchesCommitExactly() {
        let cases = [
            Gesture(magnification: 1, anchor: ViewPoint(x: 0, y: 0), pan: ViewPoint(x: 0, y: 0)),
            Gesture(magnification: 2.5, anchor: ViewPoint(x: 300, y: 120), pan: ViewPoint(x: -60, y: 40)),
            Gesture(magnification: 0.4, anchor: ViewPoint(x: 10, y: 480), pan: ViewPoint(x: 200, y: -150)),
            Gesture(magnification: 1e6, anchor: ViewPoint(x: 195, y: 250), pan: ViewPoint(x: 5, y: 5)),
            Gesture(magnification: 1e-6, anchor: ViewPoint(x: 195, y: 250), pan: ViewPoint(x: -5, y: -5))
        ]

        for gesture in cases {
            let (magnification, anchor, pan) = (gesture.magnification, gesture.anchor, gesture.pan)
            var zoom = StageZoom()
            let previewed = zoom.previewing(
                magnification: magnification, anchor: anchor, pan: pan, fitting: Self.fit
            )

            zoom.commit(magnification: magnification, anchor: anchor, pan: pan, fitting: Self.fit)

            #expect(
                zoom.resolved(fitting: Self.fit) == previewed,
                "preview and commit disagree at \(magnification)x"
            )
        }
    }

    /// Previewing is **pure**: drawing a frame must not move the stage, or a gesture would
    /// compound against itself once per frame — the exact bug the single commit exists to
    /// prevent, arriving through the preview instead.
    @Test("previewing a gesture leaves the zoom untouched")
    func previewingDoesNotMutate() {
        var zoom = StageZoom()
        zoom.commit(magnification: 2, anchor: Self.viewport.center, pan: .zero, fitting: Self.fit)
        let before = zoom

        for _ in 0 ..< 10 {
            _ = zoom.previewing(
                magnification: 3, anchor: Self.viewport.center, pan: .zero, fitting: Self.fit
            )
        }

        #expect(zoom == before)
    }

    /// **A gesture that nets out to nothing leaves the stage following the fit.**
    ///
    /// Codex round 4: pinching to 2× and back to exactly 1× stored a transform equal to the
    /// fit, which is non-`nil` and therefore stops the refit — so the next rotation or window
    /// resize would keep the design framed for the viewport it no longer has.
    @Test("an identity gesture does not take the stage off the fit")
    func anIdentityGestureKeepsFollowingTheFit() {
        var zoom = StageZoom()

        zoom.commit(magnification: 1, anchor: Self.viewport.center, pan: .zero, fitting: Self.fit)

        #expect(zoom.isFollowingFit)
        // The property that makes it matter: a changed viewport still refits.
        let narrow = StageTransform.fitting(StageGeometry.box, in: ViewSize(width: 200, height: 200))
        #expect(zoom.resolved(fitting: narrow) == narrow)
    }

    /// The other half: an identity gesture must not *undo* a zoom the user chose.
    @Test("an identity gesture leaves an explicit transform explicit")
    func anIdentityGestureKeepsAnExplicitTransform() {
        var zoom = StageZoom()
        zoom.commit(magnification: 3, anchor: Self.viewport.center, pan: .zero, fitting: Self.fit)
        let zoomed = zoom.resolved(fitting: Self.fit)

        zoom.commit(magnification: 1, anchor: Self.viewport.center, pan: .zero, fitting: Self.fit)

        #expect(!zoom.isFollowingFit)
        #expect(zoom.resolved(fitting: Self.fit) == zoomed)
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

/// One gesture's worth of input. A named value rather than a tuple, because SwiftLint caps
/// tuples at two members and the labels are worth having at the call sites anyway.
private struct Gesture {
    let magnification: Double
    let anchor: ViewPoint
    let pan: ViewPoint
}
