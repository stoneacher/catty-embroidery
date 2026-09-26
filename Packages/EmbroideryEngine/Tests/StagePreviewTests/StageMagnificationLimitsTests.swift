import StagePreview
import Testing

/// **The range the input layer and the transform have to agree on.**
///
/// `StageManipulation` compensates its rebase with the magnification it holds, which is exact
/// only if `StageTransform.pinched` applies that same factor — so the bounds are one concept with
/// two readers, and every finding in this suite came from the two disagreeing. Rounds 1, 2, 4 and
/// 5 of `/codex-review` each found a different way for them to drift apart: a clamp the tracker
/// did not know about, a baseline that moved under an animation, a floor that excluded where the
/// stage already was, and an accessibility action left on the old bounds.
///
/// Split from `StageToggleAndPanTests` when that file crossed SwiftLint's 400-line limit under
/// `--strict`.
@Suite("Stage magnification limits")
struct StageMagnificationLimitsTests {
    private static let viewport = ViewSize(width: 390, height: 500)

    private static var fit: StageTransform {
        StageTransform.fitting(StageGeometry.box, in: viewport)
    }

    // MARK: - Magnification limits

    /// The limits must describe the transform the user can *see*, not the one the model has
    /// already jumped to. ADR-028 records that the model's progress reaches 1 the moment
    /// `withAnimation` runs and only the view's shim holds the interpolated value — which is why
    /// every other method here takes `settlingAt`. Without it a pinch mid-animation is clamped
    /// against the destination's scale and the rebase compensation goes wrong again, which is
    /// round 1's High finding by another route. Found by `/codex-review` round 2.
    @Test("the magnification limits follow the visible baseline during an animation")
    func theMagnificationLimitsFollowTheVisibleBaseline() throws {
        var interaction = StageInteraction()
        let started = interaction.beginToggle(about: ViewPoint(x: 0, y: 0), fitting: Self.fit)
        _ = try #require(started)

        let visible = interaction.baseline(fitting: Self.fit, settlingAt: 0.25)
        let bounds = StageZoomBounds(fitting: Self.fit)
        let limits = interaction.magnificationLimits(fitting: Self.fit, settlingAt: 0.25)

        #expect(abs(limits.lowerBound - bounds.minimum / visible.scale) < 1e-12)
        #expect(abs(limits.upperBound - bounds.maximum / visible.scale) < 1e-12)
    }

    /// **A ratio floored by an absolute scale is a category error.** `minimumRepresentableScale`
    /// is a bound on a transform's scale, not on a magnification factor, and using it as the
    /// floor narrows the fit-aware range for a very small fit — the stage then cannot pinch down
    /// to a zoom the bounds explicitly permit. Found by `/codex-review` round 2.
    @Test("the magnification limits are a ratio, not floored by an absolute scale")
    func theMagnificationLimitsAreARatio() {
        let tiny = StageTransform(scale: 1e-6)
        var interaction = StageInteraction()
        interaction.commit(
            StageGesture(magnification: 5e7), fitting: tiny, in: Self.viewport
        )

        let baseline = interaction.baseline(fitting: tiny)
        let bounds = StageZoomBounds(fitting: tiny)
        let limits = interaction.magnificationLimits(fitting: tiny)

        #expect(baseline.scale == 50)
        #expect(abs(limits.lowerBound - bounds.minimum / baseline.scale) < 1e-18)
        #expect(limits.lowerBound < StageTransform.minimumRepresentableScale)
    }

    /// **A manipulation and an animation are mutually exclusive, and ADR-028 says so — but only
    /// `commit` enforced it, at the *end* of the gesture.** While a fit animation kept running
    /// under a live pinch, the visible baseline moved every frame, so the limits captured at
    /// `pinchBegan` stopped matching the factor `pinched` applies and a rebase jumped. Found by
    /// `/codex-review` round 3, which reached it by holding the fingers still and letting the
    /// animation advance underneath them.
    @Test("beginning a manipulation ends any animation, so the baseline stops moving")
    func beginningAManipulationEndsAnyAnimation() throws {
        var interaction = StageInteraction()
        let started = interaction.beginToggle(about: ViewPoint(x: 0, y: 0), fitting: Self.fit)
        _ = try #require(started)
        let visible = interaction.baseline(fitting: Self.fit, settlingAt: 0.25)

        interaction.beginManipulating(joining: StageManipulation(), fitting: Self.fit, settlingAt: 0.25)

        #expect(!interaction.isSettling)
        #expect(interaction.baseline(fitting: Self.fit) == visible)
        // The limits are now a property of a baseline that cannot move under the fingers.
        let before = interaction.magnificationLimits(fitting: Self.fit)
        #expect(interaction.magnificationLimits(fitting: Self.fit, settlingAt: 0.5) == before)
    }

    /// **Interrupting an animation at progress zero must leave the stage exactly as it was**, and
    /// for one that began from the fit that means *following the fit*, not holding an explicit
    /// transform that happens to equal it. `adoptsFit` gave the phase destination semantics;
    /// this is the same question at the source end. Reachable as an identity gesture landing in
    /// the same frame a double tap starts: the stage then stops refitting for good. Found by
    /// `/codex-review` round 3.
    @Test("interrupting an animation at its source keeps following the fit")
    func interruptingAnAnimationAtItsSourceKeepsFollowingTheFit() throws {
        var interaction = StageInteraction()
        let started = interaction.beginToggle(about: .zero, fitting: Self.fit)
        _ = try #require(started)

        interaction.commit(StageGesture(), fitting: Self.fit, in: Self.viewport, settlingAt: 0)

        #expect(interaction.isFollowingFit, "an identity gesture must not take the stage off the fit")
        let narrower = StageTransform.fitting(
            StageGeometry.box, in: ViewSize(width: 200, height: 200)
        )
        #expect(interaction.baseline(fitting: narrower) == narrower, "and it must still refit")
    }

    /// **A pinch of exactly 1× must stay exactly 1×, whatever the bounds.** An out-of-hoop design
    /// can be settled at a scale *below* the current fit's floor — pan at a narrow viewport, then
    /// widen it — and the limits then opened at 1.25, so `pinchBegan(scale: 1)` clamped to 1.25
    /// and the gesture stopped being an identity. Two stationary fingers moved every grabbed
    /// point but the centroid, and `StageGesture.isIdentity` — the guard ADR-028 built to keep a
    /// still gesture still — could not fire because the value it inspects had already been
    /// changed. Found by `/codex-review` round 4.
    ///
    /// The rule that fixes it is the one ADR-028 states for the fit-aware floor: the bounds may
    /// only ever *widen*. They now include the baseline the user is actually at, so 1 is always
    /// inside the range and the transform never clamps a factor the tracker allowed.
    @Test("the magnification limits always contain one, even below the fit's floor")
    func theMagnificationLimitsAlwaysContainOne() throws {
        let narrow = StageTransform(scale: 0.04)
        var interaction = StageInteraction()
        interaction.panned(by: ViewPoint(x: 10, y: 0), fitting: narrow)
        #expect(interaction.baseline(fitting: narrow).scale == 0.04)

        // The viewport widens: the fit is now 0.08, whose floor (0.05) excludes where we are.
        let wider = StageTransform(scale: 0.08)
        let limits = interaction.magnificationLimits(fitting: wider)
        #expect(limits.contains(1))

        var manipulation = StageManipulation()
        manipulation.pinchBegan(scale: 1, centroid: Self.viewport.center, within: limits)
        let resting = try #require(manipulation.gesture(in: Self.viewport))
        #expect(resting.isIdentity, "an identity pinch must survive the clamp")

        // And a small pinch is applied as asked rather than snapped up to the fit's floor.
        manipulation.pinchChanged(to: 1.01)
        let nudged = try #require(manipulation.gesture(in: Self.viewport))
        let moved = interaction.transform(with: nudged, fitting: wider, in: Self.viewport)
        #expect(abs(moved.scale - 0.04 * 1.01) < 1e-12)
    }

    /// The source-fit flag, pinned on **both** sides of its branch: an animation that began from
    /// an explicit transform must stay explicit when interrupted at its source. Without this a
    /// mutant setting `sourceFollowedFit: true` in `beginSettling` survives the suite. Found by
    /// `/codex-review` round 4.
    @Test("interrupting an explicit animation at its source stays explicit")
    func interruptingAnExplicitAnimationAtItsSourceStaysExplicit() throws {
        var interaction = StageInteraction()
        interaction.commit(
            StageGesture(magnification: 2), fitting: Self.fit, in: Self.viewport
        )
        let zoomed = interaction.baseline(fitting: Self.fit)
        let started = interaction.beginSettling(fitting: Self.fit)
        _ = try #require(started)

        interaction.interrupt(settlingAt: 0)

        #expect(!interaction.isFollowingFit)
        #expect(interaction.baseline(fitting: Self.fit) == zoomed)
    }

    /// `beginManipulating` is safe to call from every recogniser's `.began`, and with nothing
    /// animating it never takes a fit-following stage off the fit — the thing ADR-028's identity
    /// guard exists to prevent. Found by `/codex-review` round 4. Since US-314 it does change one
    /// thing, the frozen fit, so the last line pins that an identity commit releases it again.
    @Test("beginning a manipulation with nothing animating keeps following the fit")
    func beginningAManipulationWithNothingAnimatingKeepsFollowingTheFit() {
        var interaction = StageInteraction()

        interaction.beginManipulating(joining: StageManipulation(), fitting: Self.fit)
        interaction.beginManipulating(joining: StageManipulation(), fitting: Self.fit)

        #expect(interaction.isFollowingFit)
        #expect(!interaction.isSettling)

        interaction.commit(StageGesture(), fitting: Self.fit, in: Self.viewport)
        #expect(interaction.isFollowingFit)
        #expect(interaction == StageInteraction())
    }

    /// **The widened bounds must not ratchet.** Each commit makes the new transform the next
    /// call's baseline, and the bounds now include the baseline — so the obvious worry is that
    /// zooming to a limit widens the limit, letting the next pinch go further, forever. It does
    /// not, and the reason is that including a value is not extending past it: the ceiling stays
    /// `max(maximumScale, where we are)`, which a pinch can reach and never exceed, and the floor
    /// stays `min(fitFloor, where we are)`, so a stage already below its floor may stay there but
    /// cannot descend. Asserted rather than argued, because this is the shape of failure round 4's
    /// fix would have if it had one.
    @Test("repeated pinches at the limit do not ratchet the bounds")
    func repeatedPinchesAtTheLimitDoNotRatchet() {
        var interaction = StageInteraction()
        for _ in 0 ..< 6 {
            interaction.commit(
                StageGesture(magnification: 1000), fitting: Self.fit, in: Self.viewport
            )
        }
        #expect(interaction.baseline(fitting: Self.fit).scale == StageTransform.maximumScale)

        var out = StageInteraction()
        let floor = StageZoomBounds(fitting: Self.fit).minimum
        for _ in 0 ..< 6 {
            out.commit(
                StageGesture(magnification: 0.001), fitting: Self.fit, in: Self.viewport
            )
        }
        #expect(out.baseline(fitting: Self.fit).scale == floor)
    }

    /// **Zoom Out must never zoom in**, and round 4's fix made it possible for it to. Widening
    /// the bounds in `moved` but not in `adjust` created the two bounds concepts ADR-028
    /// explicitly forbids — "the adjustable action uses the same bounds as a gesture; one bounds
    /// concept, not two" — so from an explicit 0.04 under a fit whose floor is 0.05, a gesture
    /// correctly stayed at 0.04 while the accessibility action clamped *up* to 0.05 and called it
    /// zooming out. Found by `/codex-review` round 5, and it is the clearest instance on this
    /// branch of a fix creating the next finding.
    @Test("zooming out below the fit's floor never increases the scale")
    func zoomingOutBelowTheFitsFloorNeverIncreasesTheScale() {
        let narrow = StageTransform(scale: 0.04)
        var interaction = StageInteraction()
        interaction.panned(by: ViewPoint(x: 10, y: 0), fitting: narrow)

        let wider = StageTransform(scale: 0.08)
        let before = interaction.baseline(fitting: wider).scale
        interaction.adjust(.zoomOut, fitting: wider, in: Self.viewport)
        let after = interaction.baseline(fitting: wider).scale

        #expect(after <= before, "zoom out went from \(before) to \(after)")
    }
}
