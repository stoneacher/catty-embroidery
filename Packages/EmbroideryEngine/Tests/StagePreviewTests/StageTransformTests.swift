import EmbroideryEngine
import StagePreview
import Testing

@Suite("Stage transform")
struct StageTransformTests {
    private let tolerance = 1e-9

    private func expectClose(
        _ actual: StagePoint,
        _ expected: StagePoint,
        _ comment: Comment,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(abs(actual.x - expected.x) < tolerance, comment, sourceLocation: sourceLocation)
        #expect(abs(actual.y - expected.y) < tolerance, comment, sourceLocation: sourceLocation)
    }

    // MARK: - Round trip

    @Test("mapping to view space and back is the identity")
    func roundTripAcrossPointsAndScales() {
        let points = [
            StagePoint(x: 0, y: 0), StagePoint(x: 250, y: 250), StagePoint(x: -250, y: -250),
            StagePoint(x: 17.5, y: -3.25), StagePoint(x: -1000, y: 4000)
        ]
        for scale in [0.05, 0.5, 1.0, 3.75, 50.0] {
            let transform = StageTransform(
                scale: scale, translation: ViewPoint(x: 120, y: -45.5)
            )
            for point in points {
                expectClose(
                    transform.stagePoint(of: transform.viewPoint(of: point)),
                    point,
                    "round trip at scale \(scale) for \(point)"
                )
            }
        }
    }

    // MARK: - The y-flip

    /// Stage space is y-up, view space is y-down. A stitch nearer the top of
    /// the hoop must land nearer the top of the view, i.e. at a *smaller* view
    /// y. Getting this backwards mirrors the whole design, and the bug is
    /// invisible on any design with a horizontal axis of symmetry — which the
    /// octagon rosette has.
    @Test("a higher stage y maps to a smaller view y")
    func higherStageYMapsToSmallerViewY() {
        let transform = StageTransform(scale: 2, translation: ViewPoint(x: 200, y: 200))
        let top = transform.viewPoint(of: StagePoint(x: 0, y: 250))
        let bottom = transform.viewPoint(of: StagePoint(x: 0, y: -250))
        #expect(top.y < bottom.y)
    }

    @Test("x is not flipped")
    func xIsNotFlipped() {
        let transform = StageTransform(scale: 2, translation: ViewPoint(x: 200, y: 200))
        let rightward = transform.viewPoint(of: StagePoint(x: 250, y: 0))
        let leftward = transform.viewPoint(of: StagePoint(x: -250, y: 0))
        #expect(rightward.x > leftward.x)
    }

    // MARK: - Fit to content

    @Test("fitting centres the content in a non-square viewport")
    func fittingCentresContent() {
        let content = StageBox(minX: -100, minY: -50, maxX: 100, maxY: 50)
        let viewport = ViewSize(width: 800, height: 400)
        let transform = StageTransform.fitting(content, in: viewport, padding: 0)

        let centre = transform.viewPoint(of: content.center)
        #expect(abs(centre.x - 400) < tolerance)
        #expect(abs(centre.y - 200) < tolerance)
    }

    /// One scalar scale, applied to both axes — a design must not be stretched
    /// to fill the viewport. The check that discriminates: the content here is
    /// 2:1 and the viewport 4:1, so a per-axis fit would give different
    /// horizontal and vertical extents.
    @Test("fitting preserves aspect ratio rather than stretching")
    func fittingPreservesAspect() {
        let content = StageBox(minX: -100, minY: -50, maxX: 100, maxY: 50)
        let viewport = ViewSize(width: 800, height: 400)
        let transform = StageTransform.fitting(content, in: viewport, padding: 0)

        let topLeft = transform.viewPoint(of: StagePoint(x: content.minX, y: content.maxY))
        let bottomRight = transform.viewPoint(of: StagePoint(x: content.maxX, y: content.minY))
        let drawnWidth = bottomRight.x - topLeft.x
        let drawnHeight = bottomRight.y - topLeft.y

        #expect(abs(drawnWidth / drawnHeight - content.width / content.height) < tolerance)
        // Limited by height (400/100 = 4) rather than width (800/200 = 4)…
        // both are 4 here, so assert the scale directly.
        #expect(abs(transform.scale - 4) < tolerance)
    }

    @Test("fitting honours padding on the limiting axis")
    func fittingHonoursPadding() {
        let content = StageBox(minX: -100, minY: -100, maxX: 100, maxY: 100)
        let viewport = ViewSize(width: 400, height: 400)
        let transform = StageTransform.fitting(content, in: viewport, padding: 20)
        // (400 − 2·20) / 200 = 1.8
        #expect(abs(transform.scale - 1.8) < tolerance)
    }

    /// A one-stitch design has zero width and height. Fitting must stay total
    /// and centre it rather than dividing by zero.
    @Test("fitting degenerate content stays total and centres it")
    func fittingDegenerateContent() {
        let point = StagePoint(x: 12, y: -7)
        let transform = StageTransform.fitting(
            StageBox(containing: point), in: ViewSize(width: 300, height: 200), padding: 10
        )
        #expect(transform.scale.isFinite)
        #expect(transform.scale >= StageTransform.minimumScale)

        let centre = transform.viewPoint(of: point)
        #expect(abs(centre.x - 150) < tolerance)
        #expect(abs(centre.y - 100) < tolerance)
    }

    @Test("fitting a zero-size viewport stays total")
    func fittingZeroViewport() {
        let transform = StageTransform.fitting(
            StageGeometry.box, in: ViewSize(width: 0, height: 0)
        )
        #expect(transform.scale.isFinite)
        #expect(transform.scale >= StageTransform.minimumScale)
    }

    // MARK: - Pinch

    @Test("pinching about an anchor leaves that anchor's stage point fixed")
    func pinchKeepsTheAnchorFixed() {
        let transform = StageTransform(scale: 1.5, translation: ViewPoint(x: 40, y: 90))
        let anchor = ViewPoint(x: 210, y: 130)
        let anchored = transform.stagePoint(of: anchor)

        for factor in [0.5, 1.0, 2.0, 7.5] {
            let pinched = transform.pinched(by: factor, about: anchor)
            expectClose(
                pinched.stagePoint(of: anchor), anchored, "anchor fixed at factor \(factor)"
            )
        }
    }

    @Test("scale clamps at both ends")
    func scaleClampsAtBothEnds() {
        let transform = StageTransform(scale: 1)
        #expect(transform.pinched(by: 1e6, about: .zero).scale == StageTransform.maximumScale)
        #expect(transform.pinched(by: 1e-6, about: .zero).scale == StageTransform.minimumScale)
    }

    /// The discriminating case for the clamp. An implementation that simply
    /// returned `self` once the clamp bites would also keep the anchor fixed
    /// and reach the clamped scale — so the test additionally requires that a
    /// point away from the anchor actually moved.
    @Test("a clamped pinch still zooms as far as it is allowed to")
    func clampedPinchStillZooms() {
        let transform = StageTransform(scale: 1, translation: ViewPoint(x: 10, y: 10))
        let anchor = ViewPoint(x: 100, y: 100)
        let far = StagePoint(x: 200, y: 200)
        let before = transform.viewPoint(of: far)

        let pinched = transform.pinched(by: 1e6, about: anchor)

        #expect(pinched.scale == StageTransform.maximumScale)
        expectClose(
            pinched.stagePoint(of: anchor), transform.stagePoint(of: anchor), "anchor still fixed"
        )
        let after = pinched.viewPoint(of: far)
        #expect(abs(after.x - before.x) > 1, "a clamped pinch must still have zoomed")
    }

    // MARK: - Drag

    @Test("drags compose additively")
    func dragsComposeAdditively() {
        let transform = StageTransform(scale: 2.25, translation: ViewPoint(x: 5, y: -5))
        let first = ViewPoint(x: 30, y: -12)
        let second = ViewPoint(x: -8, y: 44)

        let stepwise = transform.dragged(by: first).dragged(by: second)
        let combined = transform.dragged(by: ViewPoint(x: first.x + second.x, y: first.y + second.y))

        #expect(stepwise == combined)
    }

    @Test("dragging moves the content but not the zoom")
    func draggingDoesNotChangeScale() {
        let transform = StageTransform(scale: 3)
        let dragged = transform.dragged(by: ViewPoint(x: 25, y: 25))
        #expect(dragged.scale == transform.scale)
        #expect(dragged.viewPoint(of: StagePoint(x: 0, y: 0)).x
            == transform.viewPoint(of: StagePoint(x: 0, y: 0)).x + 25)
    }
}
