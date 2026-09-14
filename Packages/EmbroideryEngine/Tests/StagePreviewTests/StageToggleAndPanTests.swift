import StagePreview
import Testing

/// **The two things US-313 adds that are not the manipulation itself**: a double-tap that
/// toggles instead of only resetting, and a pan that does not need fingers.
///
/// Both are pure package math here; US-313b wires them to a `UITapGestureRecognizer` and to four
/// named accessibility actions.
@Suite("Stage toggle and directional pan")
struct StageToggleAndPanTests {
    private static let viewport = ViewSize(width: 390, height: 500)

    private static var fit: StageTransform {
        StageTransform.fitting(StageGeometry.box, in: viewport)
    }

    private static func isClose(_ actual: ViewPoint, _ expected: ViewPoint) -> Bool {
        abs(actual.x - expected.x) < 1e-9 && abs(actual.y - expected.y) < 1e-9
    }

    /// Runs a settling animation to its end, the way the view's `Animatable` shim does.
    private static func settle(_ interaction: inout StageInteraction, _ id: Int) {
        interaction.settlingProgressed(to: 1)
        interaction.finishSettling(id)
    }

    // MARK: - The double-tap toggle

    /// **Maps and Photos zoom *in* at the tapped point; the shipped stage only ever reset to
    /// fit.** The toggle closes that gap, and the tapped point is the anchor for the same reason
    /// a pinch's centroid is: the thing under your finger is the thing you meant.
    @Test("a double tap from the fit zooms in about the tapped point")
    func aDoubleTapFromTheFitZoomsAboutTheTappedPoint() throws {
        var interaction = StageInteraction()
        let tap = ViewPoint(x: 120, y: 380)
        let grabbed = Self.fit.stagePoint(of: tap)

        let started = interaction.beginToggle(about: tap, fitting: Self.fit)
        let id = try #require(started)
        Self.settle(&interaction, id)
        let now = interaction.baseline(fitting: Self.fit)

        #expect(!interaction.isFollowingFit)
        #expect(abs(now.scale - Self.fit.scale * StageInteraction.toggleStep) < 1e-9)
        #expect(Self.isClose(now.viewPoint(of: grabbed), tap))
    }

    /// **Fit is always one more tap away** — the recovery path an assistive user relies on, and
    /// the reason the toggle can replace reset-to-fit rather than having to sit beside it.
    @Test("a second double tap returns to the fit")
    func aSecondDoubleTapReturnsToTheFit() throws {
        var interaction = StageInteraction()
        let tap = ViewPoint(x: 120, y: 380)

        let startedIn = interaction.beginToggle(about: tap, fitting: Self.fit)
        Self.settle(&interaction, try #require(startedIn))
        let startedBack = interaction.beginToggle(about: tap, fitting: Self.fit)
        Self.settle(&interaction, try #require(startedBack))

        #expect(interaction.isFollowingFit)
        #expect(interaction.baseline(fitting: Self.fit) == Self.fit)
    }

    /// A pinch to some other zoom is "not fitted", so the next double tap resets rather than
    /// zooming further — the toggle is about the fit, not about the last tap.
    @Test("a double tap after a pinch returns to the fit rather than zooming further")
    func aDoubleTapAfterAPinchReturnsToTheFit() throws {
        var interaction = StageInteraction()
        interaction.commit(
            StageGesture(magnification: 3), fitting: Self.fit, in: Self.viewport
        )

        let started = interaction.beginToggle(about: ViewPoint(x: 200, y: 250), fitting: Self.fit)
        Self.settle(&interaction, try #require(started))

        #expect(interaction.isFollowingFit)
    }

    /// The zoom-in half animates from the fit **to a transform that is not the fit**, so ending
    /// it must adopt that destination. Adopting the fit — what `finishSettling` did when every
    /// animation ended at the fit — would snap the stage back the moment the spring finished,
    /// and the zoom would last exactly as long as the animation.
    @Test("finishing the zoom-in adopts its destination rather than the fit")
    func finishingTheZoomInAdoptsItsDestination() throws {
        var interaction = StageInteraction()
        let tap = ViewPoint(x: 300, y: 120)

        let started = interaction.beginToggle(about: tap, fitting: Self.fit)
        let id = try #require(started)
        interaction.settlingProgressed(to: 1)
        let destination = interaction.baseline(fitting: Self.fit)
        interaction.finishSettling(id)

        #expect(interaction.baseline(fitting: Self.fit) == destination)
        #expect(destination != Self.fit)
    }

    /// Interrupting the zoom-in keeps what is on screen, exactly as interrupting a reset does —
    /// ADR-028's Codex round 8 rule, which must not have acquired an exception.
    @Test("interrupting the zoom-in keeps what is on screen")
    func interruptingTheZoomInKeepsWhatIsOnScreen() throws {
        var interaction = StageInteraction()
        let tap = ViewPoint(x: 300, y: 120)

        let started = interaction.beginToggle(about: tap, fitting: Self.fit)
        _ = try #require(started)
        let midway = interaction.baseline(fitting: Self.fit, settlingAt: 0.5)
        interaction.interrupt(settlingAt: 0.5)

        #expect(!interaction.isFollowingFit)
        #expect(interaction.baseline(fitting: Self.fit) == midway)
    }

    /// **An explicit transform that happens to equal the fit must still be able to go back to
    /// following it.** Two opposing pans, or a zero-delta accessibility pan, leave `settled`
    /// non-`nil` and equal to `fit`; the toggle then found nothing to animate and returned `nil`
    /// without clearing it, so the stage stayed pinned to a stale transform and a later viewport
    /// change could not refit. "Nothing to animate" is not "nothing to do". Found by
    /// `/codex-review` round 1.
    @Test("a toggle with nothing to animate still returns to following the fit")
    func aToggleWithNothingToAnimateStillFollowsTheFit() {
        var interaction = StageInteraction()
        interaction.panned(by: .zero, fitting: Self.fit)
        #expect(!interaction.isFollowingFit)

        let started = interaction.beginToggle(about: Self.viewport.center, fitting: Self.fit)

        #expect(started == nil, "there is nothing to animate")
        #expect(interaction.isFollowingFit, "but the fit is adopted anyway")
    }

    // MARK: - The directional pan

    /// **The gap this closes is live in the shipped app**: `adjust` anchors on the viewport's
    /// centre, so zoom is reachable without gestures but pan is not — an assistive user can zoom
    /// to 3× and then only ever see the middle of their design.
    @Test("a directional pan moves the stage by the delta and takes control")
    func aDirectionalPanMovesTheStageByTheDelta() {
        var interaction = StageInteraction()
        let probe = Self.fit.stagePoint(of: Self.viewport.center)
        let delta = ViewPoint(x: -40, y: 25)

        interaction.panned(by: delta, fitting: Self.fit)
        let now = interaction.baseline(fitting: Self.fit)

        #expect(!interaction.isFollowingFit)
        #expect(Self.isClose(
            now.viewPoint(of: probe),
            ViewPoint(x: Self.viewport.center.x + delta.x, y: Self.viewport.center.y + delta.y)
        ))
    }

    /// Repeated activations accumulate, which is what makes reaching a corner possible at all.
    @Test("directional pans accumulate")
    func directionalPansAccumulate() {
        var interaction = StageInteraction()
        let probe = Self.fit.stagePoint(of: Self.viewport.center)

        for _ in 0 ..< 3 {
            interaction.panned(by: ViewPoint(x: -40, y: 0), fitting: Self.fit)
        }

        #expect(Self.isClose(
            interaction.baseline(fitting: Self.fit).viewPoint(of: probe),
            ViewPoint(x: Self.viewport.center.x - 120, y: Self.viewport.center.y)
        ))
    }

    /// A pan takes over from a fit animation at what is on screen, like every other thing that
    /// takes control — one answer to "what happens when you interrupt a fit", not one per caller.
    @Test("a directional pan interrupts a fit animation at what is on screen")
    func aDirectionalPanInterruptsAFitAnimation() throws {
        var interaction = StageInteraction()
        interaction.commit(
            StageGesture(magnification: 3), fitting: Self.fit, in: Self.viewport
        )
        let started = interaction.beginSettling(fitting: Self.fit)
        _ = try #require(started)
        let midway = interaction.baseline(fitting: Self.fit, settlingAt: 0.5)

        interaction.panned(by: ViewPoint(x: -40, y: 0), fitting: Self.fit, settlingAt: 0.5)

        #expect(!interaction.isSettling)
        #expect(interaction.baseline(fitting: Self.fit) == midway.dragged(by: ViewPoint(x: -40, y: 0)))
    }
}
