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

        #expect(started != nil)
        #expect(interaction.isSettling)
        #expect(interaction.baseline(fitting: Self.fit) == zoomed, "progress 0 is where it started")

        interaction.settlingProgressed(to: 1)
        #expect(interaction.baseline(fitting: Self.fit) == Self.fit)

        interaction.finishSettling(started ?? -1)
        #expect(interaction.isFollowingFit)
        #expect(!interaction.isSettling)
    }

    /// **Mid-animation, the frame is live and the raster is not composited.**
    ///
    /// Codex round 7 mutated `rendering` to ignore `isSettling` and all 22 interaction tests
    /// stayed green — which would let the stale raster be drawn under a reset instead of
    /// re-stroking at the interpolated transform, reintroducing exactly the "content does not
    /// return into frame" failure ADR-028 records. Every assertion here fails under that
    /// mutation.
    @Test("a settling stage renders live, at the interpolated transform, keyed on the old bake")
    func aSettlingStageRendersLive() {
        var interaction = StageInteraction()
        interaction.commit(Self.pinch(4), fitting: Self.fit, in: Self.viewport)
        let zoomed = interaction.baseline(fitting: Self.fit)
        _ = interaction.beginSettling(fitting: Self.fit)

        let render = interaction.rendering(
            gesture: nil, fitting: Self.fit, in: Self.viewport, settlingAt: 0.25
        )

        #expect(!render.canUseRaster, "a reset must re-stroke, not composite a stale raster")
        #expect(render.bake == zoomed, "the raster stays keyed on where it was baked")
        #expect(
            render.current == interaction.baseline(fitting: Self.fit, settlingAt: 0.25),
            "the frame is drawn at the interpolated transform"
        )
        #expect(render.current != zoomed)
        #expect(render.current != Self.fit)
    }

    /// **An intermediate step is a real intermediate transform.**
    ///
    /// Codex round 7 mutated `settlingProgressed` to store 1 always — a visible snap instead of
    /// an animation — and every test stayed green, because the suite only ever observed
    /// progress 0 and 1. This asserts a quarter of the way is a quarter of the way.
    @Test("a quarter of the way through is a quarter of the way")
    func anIntermediateStepInterpolates() {
        var interaction = StageInteraction()
        interaction.commit(Self.pinch(4), fitting: Self.fit, in: Self.viewport)
        let zoomed = interaction.baseline(fitting: Self.fit)
        _ = interaction.beginSettling(fitting: Self.fit)

        interaction.settlingProgressed(to: 0.25)

        #expect(interaction.settlingProgress == 0.25)
        #expect(interaction.baseline(fitting: Self.fit) == zoomed.interpolated(to: Self.fit, progress: 0.25))
        // Strictly between the endpoints, which a snap to either would fail.
        #expect(interaction.baseline(fitting: Self.fit) != zoomed)
        #expect(interaction.baseline(fitting: Self.fit) != Self.fit)
    }

    /// **A completion must own the animation it ends.**
    ///
    /// Codex round 7: idempotence alone protects a late completion only when *nothing* is
    /// settling. Begin A, interrupt it with a gesture, begin B, and A's completion found B's
    /// phase and ended it early — the animation the user is watching stops a third of the way
    /// through. The id handed out at `beginSettling` is what makes "mine" checkable.
    @Test("a completion from an interrupted animation cannot end a newer one")
    func aStaleCompletionCannotEndANewerAnimation() {
        var interaction = StageInteraction()
        interaction.commit(Self.pinch(4), fitting: Self.fit, in: Self.viewport)
        let first = interaction.beginSettling(fitting: Self.fit)
        interaction.settlingProgressed(to: 0.5)
        interaction.commit(Self.pan(x: 20, y: 0), fitting: Self.fit, in: Self.viewport)
        let second = interaction.beginSettling(fitting: Self.fit)

        #expect(first != nil)
        #expect(second != nil)
        #expect(first != second, "premise: the two animations have distinct identities")

        // A's completion arrives late, while B is running.
        interaction.finishSettling(first ?? -1)

        #expect(interaction.isSettling, "B must still be animating")

        // And B's own completion still works.
        interaction.finishSettling(second ?? -1)
        #expect(!interaction.isSettling)
        #expect(interaction.isFollowingFit)
    }

    /// **The case the real SwiftUI path takes, and the one every other test here missed.**
    ///
    /// `withAnimation` sets the model's progress to 1 *immediately*; only the view's
    /// `Animatable` shim holds the interpolated value. So the honest reproduction of an
    /// interruption is stored progress 1 with a visible progress of 0.5 — and every earlier test
    /// drove `settlingProgressed(to: 0.5)`, making the two agree and hiding the discontinuity
    /// (Codex round 8). Interrupting must adopt what is on **screen**, not the destination.
    @Test("interrupting an animation adopts the visible transform, not its destination")
    func interruptingAdoptsTheVisibleTransform() {
        var interaction = StageInteraction()
        interaction.commit(Self.pinch(4), fitting: Self.fit, in: Self.viewport)
        let zoomed = interaction.baseline(fitting: Self.fit)
        _ = interaction.beginSettling(fitting: Self.fit)
        interaction.settlingProgressed(to: 1)

        let visible = interaction.baseline(fitting: Self.fit, settlingAt: 0.5)
        interaction.commit(
            Self.pan(x: 20, y: 0), fitting: Self.fit, in: Self.viewport, settlingAt: 0.5
        )

        #expect(interaction.baseline(fitting: Self.fit) == visible.dragged(by: ViewPoint(x: 20, y: 0)))
        // Which is neither endpoint plus the drag — the two failures this forbids.
        #expect(interaction.baseline(fitting: Self.fit) != Self.fit.dragged(by: ViewPoint(x: 20, y: 0)))
        #expect(interaction.baseline(fitting: Self.fit) != zoomed.dragged(by: ViewPoint(x: 20, y: 0)))
    }

    /// The same for the accessibility path, which had the identical defect.
    @Test("an adjustment mid-animation zooms from the visible transform")
    func adjustingMidAnimationUsesTheVisibleTransform() {
        var interaction = StageInteraction()
        interaction.commit(Self.pinch(4), fitting: Self.fit, in: Self.viewport)
        _ = interaction.beginSettling(fitting: Self.fit)
        interaction.settlingProgressed(to: 1)
        let visible = interaction.baseline(fitting: Self.fit, settlingAt: 0.5)

        interaction.adjust(.zoomIn, fitting: Self.fit, in: Self.viewport, settlingAt: 0.5)

        let expected = visible.pinched(
            by: StageInteraction.adjustmentStep,
            about: Self.viewport.center,
            within: StageZoomBounds(fitting: Self.fit)
        )
        #expect(interaction.baseline(fitting: Self.fit) == expected)
    }

    /// A *completed* animation still adopts the destination and goes back to following the fit —
    /// the guard is on progress, so it must not turn every completion into an explicit
    /// transform, which would silently disable the refit.
    @Test("a completed animation still returns to following the fit")
    func aCompletedAnimationFollowsTheFit() {
        var interaction = StageInteraction()
        interaction.commit(Self.pinch(4), fitting: Self.fit, in: Self.viewport)
        _ = interaction.beginSettling(fitting: Self.fit)

        interaction.interrupt(settlingAt: 1)

        #expect(interaction.isFollowingFit)
        #expect(!interaction.isSettling)
    }

    /// A fitted stage has nothing to animate, and the caller is told so rather than starting a
    /// spring that renders one frame and stops.
    @Test("settling an already-fitted stage does nothing and says so")
    func settlingAFittedStageDoesNothing() {
        var interaction = StageInteraction()

        let started = interaction.beginSettling(fitting: Self.fit)

        #expect(started == nil)
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

        #expect(restarted == nil)
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
        let stale = interaction.beginSettling(fitting: Self.fit)
        interaction.settlingProgressed(to: 0.5)

        interaction.adjust(.zoomIn, fitting: Self.fit, in: Self.viewport)
        let adjusted = interaction.baseline(fitting: Self.fit)

        // The stale completion arrives late and must not undo it.
        interaction.finishSettling(stale ?? -1)

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
        let stale = interaction.beginSettling(fitting: Self.fit)
        interaction.settlingProgressed(to: 0.5)
        interaction.commit(Self.pan(x: 20, y: 0), fitting: Self.fit, in: Self.viewport)
        let afterGesture = interaction

        interaction.finishSettling(stale ?? -1)
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
        #expect(interaction.baseline(fitting: Self.fit) == Self.fit)
        // **Not `== StageInteraction()`**, which is what this asserted first and is wrong: the
        // settling id counter is monotonic and deliberately survives a reset. Were it to go
        // back to zero, an id could be reused and a completion from before the reset could
        // match a *later* animation — the very ownership bug the id exists to prevent.
        #expect(interaction != StageInteraction())
    }
}
