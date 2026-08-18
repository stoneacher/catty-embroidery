import StagePreview
import Testing

/// The fit animation and the adjustable action — the transitions, split from the suite above
/// only because SwiftLint caps a type body at 250 lines.
@Suite("Stage interaction transitions")
struct StageInteractionTransitionTests {
    private static let viewport = ViewSize(width: 390, height: 500)

    private static var fit: StageTransform {
        StageTransform.fitting(StageGeometry.box, in: viewport)
    }

    private static func pinch(_ magnification: Double) -> StageGesture {
        StageGesture(magnification: magnification)
    }

    private static func pan(x: Double, y: Double) -> StageGesture {
        StageGesture(panX: x, panY: y)
    }

    @Test("settling animates from the committed transform to the fit")
    func settlingAnimatesToTheFit() {
        var interaction = StageInteraction()
        interaction.commit(Self.pinch(4), fitting: Self.fit, in: Self.viewport)
        let zoomed = interaction.baseline(fitting: Self.fit)

        let started = interaction.beginSettling(fitting: Self.fit)

        #expect(started)
        #expect(interaction.isSettling)
        #expect(interaction.baseline(fitting: Self.fit) == zoomed, "progress 0 is where it started")

        interaction.settlingProgressed(to: 1)
        #expect(interaction.baseline(fitting: Self.fit) == Self.fit)

        interaction.finishSettling()
        #expect(interaction.isFollowingFit)
        #expect(!interaction.isSettling)
    }

    /// A fitted stage has nothing to animate, and the caller is told so rather than starting a
    /// spring that renders one frame and stops.
    @Test("settling an already-fitted stage does nothing and says so")
    func settlingAFittedStageDoesNothing() {
        var interaction = StageInteraction()

        let started = interaction.beginSettling(fitting: Self.fit)

        #expect(!started)
        #expect(!interaction.isSettling)
    }

    /// Round 4's defect: a second double-tap mid-animation animated from the *pre-animation*
    /// transform and snapped backwards past what was on screen.
    @Test("a second settle mid-animation is a no-op rather than a jump backwards")
    func asecondSettleMidAnimationDoesNotJump() {
        var interaction = StageInteraction()
        interaction.commit(Self.pinch(4), fitting: Self.fit, in: Self.viewport)
        _ = interaction.beginSettling(fitting: Self.fit)
        interaction.settlingProgressed(to: 0.5)

        let restarted = interaction.beginSettling(fitting: Self.fit)

        #expect(!restarted)
        #expect(interaction.isFollowingFit, "the interrupted settle adopted its destination")
        #expect(interaction.baseline(fitting: Self.fit) == Self.fit)
    }

    /// Round 3's other defect: a gesture interrupting the animation committed against the
    /// pre-animation transform, so releasing jumped.
    @Test("a gesture interrupting the animation commits from where the animation was heading")
    func aGestureInterruptingTheAnimationCommitsFromItsDestination() {
        var interaction = StageInteraction()
        interaction.commit(Self.pinch(4), fitting: Self.fit, in: Self.viewport)
        _ = interaction.beginSettling(fitting: Self.fit)
        interaction.settlingProgressed(to: 0.5)

        interaction.commit(Self.pan(x: 20, y: 0), fitting: Self.fit, in: Self.viewport)

        #expect(!interaction.isSettling)
        // Fit plus the pan — not the 4× transform plus the pan.
        #expect(interaction.baseline(fitting: Self.fit) == Self.fit.dragged(by: ViewPoint(x: 20, y: 0)))
    }

    /// Round 3's third defect: an accessibility adjustment during the animation was discarded by
    /// the completion handler 0.35 s later.
    @Test("an adjustment during the animation survives it")
    func anAdjustmentDuringTheAnimationSurvives() {
        var interaction = StageInteraction()
        interaction.commit(Self.pinch(4), fitting: Self.fit, in: Self.viewport)
        _ = interaction.beginSettling(fitting: Self.fit)
        interaction.settlingProgressed(to: 0.5)

        interaction.adjust(.zoomIn, fitting: Self.fit, in: Self.viewport)
        let adjusted = interaction.baseline(fitting: Self.fit)

        // The stale completion arrives late and must not undo it.
        interaction.finishSettling()

        #expect(interaction.baseline(fitting: Self.fit) == adjusted)
        #expect(!interaction.isFollowingFit)
    }

    /// **What replaced the generation token.** A completion from an interrupted animation finds
    /// nothing settling and does nothing — no counter to keep in step, and no way to disarm the
    /// wrong one.
    @Test("a stale completion is inert")
    func aStaleCompletionIsInert() {
        var interaction = StageInteraction()
        interaction.commit(Self.pinch(4), fitting: Self.fit, in: Self.viewport)
        _ = interaction.beginSettling(fitting: Self.fit)
        interaction.settlingProgressed(to: 0.5)
        interaction.commit(Self.pan(x: 20, y: 0), fitting: Self.fit, in: Self.viewport)
        let afterGesture = interaction

        interaction.finishSettling()
        interaction.settlingProgressed(to: 1)

        #expect(interaction == afterGesture)
    }

    // MARK: - The adjustable action

    @Test("the viewport centre is fixed by an adjustment")
    func theViewportCentreIsFixed() {
        var interaction = StageInteraction()
        interaction.commit(
            StageGesture(magnification: 2, anchorUnitX: 0.1, anchorUnitY: 0.2, panX: -75, panY: 30),
            fitting: Self.fit,
            in: Self.viewport
        )
        let centre = Self.viewport.center
        let before = interaction.baseline(fitting: Self.fit).stagePoint(of: centre)

        interaction.adjust(.zoomIn, fitting: Self.fit, in: Self.viewport)

        let after = interaction.baseline(fitting: Self.fit).stagePoint(of: centre)
        #expect(abs(after.x - before.x) < 1e-9)
        #expect(abs(after.y - before.y) < 1e-9)
    }

    @Test("zooming in and back out round-trips")
    func adjustmentsRoundTrip() {
        var interaction = StageInteraction()

        interaction.adjust(.zoomIn, fitting: Self.fit, in: Self.viewport)
        interaction.adjust(.zoomOut, fitting: Self.fit, in: Self.viewport)

        let resolved = interaction.baseline(fitting: Self.fit)
        #expect(abs(resolved.scale - Self.fit.scale) < 1e-9)
        #expect(abs(resolved.translation.x - Self.fit.translation.x) < 1e-9)
    }

    @Test("adjustments stop exactly at both bounds")
    func adjustmentsStopAtTheBounds() {
        var zoomedIn = StageInteraction()
        var zoomedOut = StageInteraction()
        for _ in 0 ..< 40 {
            zoomedIn.adjust(.zoomIn, fitting: Self.fit, in: Self.viewport)
            zoomedOut.adjust(.zoomOut, fitting: Self.fit, in: Self.viewport)
        }

        #expect(zoomedIn.baseline(fitting: Self.fit).scale == StageTransform.maximumScale)
        #expect(
            zoomedOut.baseline(fitting: Self.fit).scale == StageZoomBounds(fitting: Self.fit).minimum
        )
    }

    /// A documentation pin: criterion 9 obliges the close-out to record the step, so the number
    /// is fixed here rather than left free to drift from what ADR-028 says.
    @Test("the adjustment step is the documented 1.5×")
    func theAdjustmentStepIsDocumented() {
        #expect(StageInteraction.adjustmentStep == 1.5)
    }

    /// The floor is the *fit-aware* one for the adjustable action too, so an assistive user on
    /// an out-of-hoop design can reach the whole design and not 11 % short of it.
    @Test("on an out-of-hoop design the adjustable floor is that design's own fit")
    func theAdjustableFloorFollowsAnOutOfHoopFit() {
        let wide = StageTransform.fitting(
            StageBox(minX: -3201, minY: -20, maxX: 3201, maxY: 20),
            in: ViewSize(width: 288, height: 288)
        )
        #expect(wide.scale < StageTransform.minimumScale, "fixture premise")
        var interaction = StageInteraction()

        for _ in 0 ..< 40 {
            interaction.adjust(.zoomOut, fitting: wide, in: ViewSize(width: 288, height: 288))
        }

        #expect(interaction.baseline(fitting: wide).scale == wide.scale)
    }

    /// An adjustment must make the transform explicit, or the next refit would discard it.
    @Test("adjusting a fitted stage makes its transform explicit")
    func adjustingMakesTheTransformExplicit() {
        var interaction = StageInteraction()

        interaction.adjust(.zoomIn, fitting: Self.fit, in: Self.viewport)

        #expect(!interaction.isFollowingFit)
        let narrow = StageTransform.fitting(StageGeometry.box, in: ViewSize(width: 200, height: 200))
        #expect(interaction.baseline(fitting: narrow) == interaction.baseline(fitting: Self.fit))
    }

    // MARK: - Magnification, as spoken

    @Test("magnification is measured against the fit and includes a gesture in flight")
    func magnificationIncludesTheGestureInFlight() {
        var interaction = StageInteraction()
        #expect(interaction.magnification(gesture: nil, fitting: Self.fit, in: Self.viewport) == 1)

        let live = interaction.magnification(
            gesture: Self.pinch(3), fitting: Self.fit, in: Self.viewport
        )
        #expect(abs(live - 3) < 1e-9, "a zoom in progress must be spoken as it looks")

        interaction.commit(Self.pinch(3), fitting: Self.fit, in: Self.viewport)
        #expect(
            abs(interaction.magnification(gesture: nil, fitting: Self.fit, in: Self.viewport) - 3)
                < 1e-9
        )
    }

    @Test("following the fit again resets everything")
    func followingTheFitAgainResets() {
        var interaction = StageInteraction()
        interaction.commit(Self.pinch(4), fitting: Self.fit, in: Self.viewport)
        _ = interaction.beginSettling(fitting: Self.fit)

        interaction.followFit()

        #expect(interaction.isFollowingFit)
        #expect(!interaction.isSettling)
        #expect(interaction == StageInteraction())
    }
}
