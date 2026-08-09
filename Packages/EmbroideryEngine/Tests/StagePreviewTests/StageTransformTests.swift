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
    /// to fill the viewport.
    ///
    /// **The content and viewport aspects must differ, or the test proves
    /// nothing** (Codex round 1). An earlier version used 2:1 content in a 2:1
    /// viewport and claimed the viewport was 4:1; there the width-only and
    /// height-only fits both give scale 4, so a per-axis implementation passed.
    /// Both cases here are asymmetric, and the two limiting axes are covered in
    /// turn so neither a width-only nor a height-only fit survives.
    @Test(
        "fitting preserves aspect ratio rather than stretching",
        arguments: [
            // 2:1 content in a 4:3 viewport — width-limited: 800/200 = 4 vs 600/100 = 6.
            (ViewSize(width: 800, height: 600), 4.0),
            // …and height-limited: 200/100 = 2 vs 800/200 = 4.
            (ViewSize(width: 800, height: 200), 2.0)
        ]
    )
    func fittingPreservesAspect(_ viewport: ViewSize, _ expectedScale: Double) {
        let content = StageBox(minX: -100, minY: -50, maxX: 100, maxY: 50)
        let transform = StageTransform.fitting(content, in: viewport, padding: 0)

        let topLeft = transform.viewPoint(of: StagePoint(x: content.minX, y: content.maxY))
        let bottomRight = transform.viewPoint(of: StagePoint(x: content.maxX, y: content.minY))
        let drawnWidth = bottomRight.x - topLeft.x
        let drawnHeight = bottomRight.y - topLeft.y

        #expect(abs(drawnWidth / drawnHeight - content.width / content.height) < tolerance)
        #expect(abs(transform.scale - expectedScale) < tolerance)
        // The content fits: neither axis overflows the viewport.
        #expect(drawnWidth <= viewport.width + tolerance)
        #expect(drawnHeight <= viewport.height + tolerance)
    }

    /// The Medium from Codex round 1. `StageBox.center` computed as
    /// `(minX + maxX) / 2` overflows to infinity at extreme finite
    /// coordinates, and the infinity propagates into the translation — so a
    /// finite, perfectly valid one-stitch design yields an unusable transform.
    ///
    /// Reachable through the preview because ADR-021 is event-driven: the event
    /// carries the stage point whether or not the *stream* later rejects it
    /// under ADR-020, and ADR-007 bounds nothing.
    @Test("an extreme but finite coordinate does not produce an infinite transform")
    func extremeFiniteCoordinateStaysFinite() throws {
        var list = StitchDisplayList()
        list.append(previewStitch(.greatestFiniteMagnitude, .greatestFiniteMagnitude))
        let bounds = try #require(list.bounds)
        expectUsableFit(bounds)
    }

    /// Every finite box must yield a finite, *usable* transform.
    ///
    /// The third case is the one round 1's fix missed (Codex round 2): the
    /// centre is finite there, but `centre.x × scale` still overflowed, because
    /// the *other* axis had an extent and pulled the scale above 1. Fixing the
    /// midpoint alone was not enough — the product needed bounding too.
    @Test(
        "every finite box yields a finite transform",
        arguments: [
            StageBox(
                minX: -.greatestFiniteMagnitude, minY: -.greatestFiniteMagnitude,
                maxX: .greatestFiniteMagnitude, maxY: .greatestFiniteMagnitude
            ),
            StageBox(
                minX: .greatestFiniteMagnitude, minY: 0,
                maxX: .greatestFiniteMagnitude, maxY: 1
            ),
            StageBox(
                minX: 0, minY: -.greatestFiniteMagnitude,
                maxX: 1, maxY: -.greatestFiniteMagnitude
            ),
            StageBox(containing: StagePoint(x: .leastNonzeroMagnitude, y: .leastNonzeroMagnitude)),
            // Codex round 3's brute-forced counterexample. The round-2 fix
            // bounded the scale by `greatestFiniteMagnitude / |centre|`, but
            // that division *rounds up*: here the ceiling comes back as
            // 1.2000448438435127 and `centre.x * scale` overflowed anyway.
            StageBox(
                minX: Double(bitPattern: 0x7FEA_AA69_5C4B_773D), minY: 0,
                maxX: Double(bitPattern: 0x7FEA_AA69_5C4B_773D), maxY: 1
            )
        ]
    )
    func everyFiniteBoxYieldsAFiniteTransform(_ bounds: StageBox) {
        expectUsableFit(bounds)
    }

    /// A search over the top binade, because the counterexample above was found
    /// by brute force rather than by reasoning — and reasoning about this
    /// product has now been wrong twice. A property this cheap to check should
    /// be checked rather than argued.
    @Test("no finite one-point box yields an infinite transform")
    func noFiniteBoxYieldsAnInfiniteTransform() {
        var bits: UInt64 = 0x7FE0_0000_0000_0000
        while bits < 0x7FF0_0000_0000_0000 {
            let value = Double(bitPattern: bits)
            let bounds = StageBox(minX: value, minY: 0, maxX: value, maxY: 1)
            let transform = StageTransform.fitting(bounds, in: ViewSize(width: 300, height: 300))
            #expect(transform.translation.x.isFinite, "overflowed at bit pattern \(bits)")
            #expect(transform.translation.y.isFinite, "overflowed at bit pattern \(bits)")
            bits &+= 0x0000_4000_0000_0000
        }
    }

    /// `pinched` multiplies a stage coordinate by the zoom exactly as `fitting`
    /// does, and the round-2 fix closed only `fitting` (Codex round 3). A zoom
    /// that cannot be represented is refused rather than returned as infinity.
    @Test("pinching a design at an extreme coordinate cannot produce an infinite transform")
    func pinchAtExtremeCoordinateStaysFinite() {
        let bounds = StageBox(containing: StagePoint(x: .greatestFiniteMagnitude, y: 0))
        let fitted = StageTransform.fitting(bounds, in: ViewSize(width: 300, height: 300))

        for factor in [0.5, 2.0, 1e6] {
            let pinched = fitted.pinched(by: factor, about: ViewPoint(x: 150, y: 150))
            #expect(pinched.scale.isFinite)
            #expect(pinched.translation.x.isFinite, "factor \(factor)")
            #expect(pinched.translation.y.isFinite, "factor \(factor)")
        }
    }

    /// The refusal must not leak into ordinary use: a normal design still zooms.
    @Test("an ordinary pinch is unaffected by the overflow guard")
    func ordinaryPinchStillZooms() {
        let transform = StageTransform(scale: 1, translation: ViewPoint(x: 10, y: 10))
        let pinched = transform.pinched(by: 2, about: ViewPoint(x: 100, y: 100))
        #expect(pinched.scale == 2)
        #expect(pinched != transform)
    }

    /// Finiteness of the *fields* is not usability — round 1's version stopped
    /// there and would have passed while the transform mapped every point to
    /// something unusable. The mapping itself has to stay finite.
    private func expectUsableFit(
        _ bounds: StageBox,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(bounds.center.x.isFinite, sourceLocation: sourceLocation)
        #expect(bounds.center.y.isFinite, sourceLocation: sourceLocation)

        let transform = StageTransform.fitting(bounds, in: ViewSize(width: 300, height: 300))
        #expect(transform.scale.isFinite, sourceLocation: sourceLocation)
        #expect(transform.scale > 0, sourceLocation: sourceLocation)
        #expect(transform.translation.x.isFinite, sourceLocation: sourceLocation)
        #expect(transform.translation.y.isFinite, sourceLocation: sourceLocation)

        // The guarantee is that the *content* maps finitely — every corner, not
        // just the centre. "The fields are finite" was the weaker claim that
        // let round 2's fix look complete.
        let corners = [
            bounds.center,
            StagePoint(x: bounds.minX, y: bounds.minY),
            StagePoint(x: bounds.maxX, y: bounds.minY),
            StagePoint(x: bounds.minX, y: bounds.maxY),
            StagePoint(x: bounds.maxX, y: bounds.maxY)
        ]
        for corner in corners {
            let mapped = transform.viewPoint(of: corner)
            #expect(mapped.x.isFinite, "corner \(corner)", sourceLocation: sourceLocation)
            #expect(mapped.y.isFinite, "corner \(corner)", sourceLocation: sourceLocation)
        }
    }

    /// And at ordinary magnitudes the fit is *correct*, not merely finite: the
    /// content centre lands on the viewport centre. This is the assertion the
    /// extreme cases cannot make — near `greatestFiniteMagnitude` the viewport
    /// offset is below one ulp of the coordinate, so exact centring is
    /// unrepresentable in `Double` and no different formula recovers it. The
    /// guarantee `fitting` makes out there is finite and usable, not exact.
    @Test(
        "at ordinary magnitudes the content centre lands on the viewport centre",
        arguments: [0.0, 1000.0, 1e6, 1e12]
    )
    func fittingCentresContentAtOrdinaryMagnitudes(_ offset: Double) {
        let bounds = StageBox(
            minX: offset - 100, minY: offset - 50, maxX: offset + 100, maxY: offset + 50
        )
        let viewport = ViewSize(width: 800, height: 600)
        let transform = StageTransform.fitting(bounds, in: viewport, padding: 0)

        let mapped = transform.viewPoint(of: bounds.center)
        let slack = 1e-9 * Swift.max(offset, 1)
        #expect(abs(mapped.x - viewport.width / 2) <= slack)
        #expect(abs(mapped.y - viewport.height / 2) <= slack)
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
