import EmbroideryEngine
import StagePreview
import Testing

/// **The fit cannot move while fingers are down** — US-314, and ADR-028's claim made true
/// rather than assumed.
///
/// Every manipulation test before this suite passed the same fit on every frame, which is exactly
/// why the defect survived US-307, US-313a and six review rounds: while the stage follows the
/// fit, the baseline is `settled ?? fit` and `fit` is a per-frame parameter the view recomputes
/// from the display list. A run whose design grows past the hoop mid-pinch changed the fit, the
/// drawn transform and the bake key under the fingers. So every test here drives **two different
/// fits through one manipulation**.
///
/// The fixture is Codex's reproduction from US-313a round 2, kept to its numbers: a 100 × 100
/// viewport, a pinch grabbed at (20, 20) and doubled, then one frame at fit scale 1 and one at
/// 0.5. Before this story the grabbed point was drawn at x = 20 in the first and x = 0 in the
/// second. All values are dyadic, so the comparisons are exact.
@Suite("Stage frozen fit")
struct StageFrozenFitTests {
    private static let viewport = ViewSize(width: 100, height: 100)
    /// The fit when the fingers landed.
    private static let fitA = StageTransform(scale: 1)
    /// The fit after the design grew past the hoop, mid-manipulation.
    private static let fitB = StageTransform(scale: 0.5)
    private static let grab = ViewPoint(x: 20, y: 20)

    /// The stage point under the fingers when they landed.
    private static var grabbed: StagePoint {
        fitA.stagePoint(of: grab)
    }

    /// The order two channels can begin in. ADR-031: a pan and a pinch have independent
    /// lifecycles, so either can be the first.
    enum FirstChannel: CaseIterable, Sendable {
        case pan
        case pinch
    }

    /// Pan begun, pinch grabbed at `grab` and doubled — all at `fitA`, the coordinator's order:
    /// `beginManipulating` before each channel's begin, limits read after it.
    private static func grabbedPinch(
        _ interaction: inout StageInteraction,
        _ manipulation: inout StageManipulation
    ) {
        interaction.beginManipulating(joining: manipulation, fitting: fitA)
        manipulation.panBegan(at: .zero)
        interaction.beginManipulating(joining: manipulation, fitting: fitA)
        manipulation.pinchBegan(
            scale: 1, centroid: grab, within: interaction.magnificationLimits(fitting: fitA)
        )
        manipulation.pinchChanged(to: 2)
    }

    private static func frame(
        _ interaction: StageInteraction,
        _ manipulation: StageManipulation,
        at fit: StageTransform
    ) -> StageRenderTransform {
        interaction.rendering(
            gesture: manipulation.gesture(in: viewport), fitting: fit, in: viewport
        )
    }

    private static func finished(_ manipulation: inout StageManipulation) throws -> StageGesture {
        manipulation.pinchEnded()
        manipulation.panEnded()
        let gesture = manipulation.finish(in: viewport, touchesRemain: false)
        return try #require(gesture)
    }

    // MARK: - Test-first plan 1 and 2: the frame holds

    @Test("the grabbed point stays under the fingers while the fit changes")
    func theGrabbedPointStaysUnderTheFingersWhileTheFitChanges() {
        var interaction = StageInteraction()
        var manipulation = StageManipulation()
        Self.grabbedPinch(&interaction, &manipulation)

        let before = Self.frame(interaction, manipulation, at: Self.fitA)
        let after = Self.frame(interaction, manipulation, at: Self.fitB)

        #expect(before.current.viewPoint(of: Self.grabbed) == Self.grab)
        #expect(after.current.viewPoint(of: Self.grabbed) == Self.grab)
    }

    /// The bake key is ADR-009's cache key: a key that moves mid-gesture re-rasterises the
    /// settled prefix under the fingers, which is ADR-028's Codex round 2 defect exactly.
    @Test("the bake key holds while the fit changes")
    func theBakeKeyHoldsWhileTheFitChanges() {
        var interaction = StageInteraction()
        var manipulation = StageManipulation()
        Self.grabbedPinch(&interaction, &manipulation)

        let before = Self.frame(interaction, manipulation, at: Self.fitA)
        let after = Self.frame(interaction, manipulation, at: Self.fitB)

        #expect(before.bake == Self.fitA)
        #expect(after.bake == Self.fitA)
        #expect(!before.canUseRaster)
        #expect(!after.canUseRaster)
    }

    /// **The clamp reads the frozen fit too, not only the baseline** — the half of the design
    /// the other tests cannot see, because they all start from `settled == nil` and pinch far
    /// from either bound. Zoomed to scale 1 over a tiny fit (0.01), the floor is 0.01, so a
    /// pinch to 0.02 is honoured; if the fit grows to 0.05 mid-pinch, a clamp against the live
    /// fit raises the floor to 0.05 while the tracker still holds 0.02, and the next rebase
    /// jumps. Found as a blind spot by `/codex-review` round 1.
    @Test("the pinch clamp holds while the fit changes under a zoomed stage")
    func thePinchClampHoldsUnderAZoomedStage() {
        let tiny = StageTransform(scale: 0.01)
        let grown = StageTransform(scale: 0.05)
        var interaction = StageInteraction()
        interaction.commit(StageGesture(magnification: 100), fitting: tiny, in: Self.viewport)
        #expect(interaction.settled?.scale == 1)

        var manipulation = StageManipulation()
        interaction.beginManipulating(joining: manipulation, fitting: tiny)
        manipulation.pinchBegan(
            scale: 1, centroid: Self.grab, within: interaction.magnificationLimits(fitting: tiny)
        )
        manipulation.pinchChanged(to: 0.02)

        let before = Self.frame(interaction, manipulation, at: tiny)
        let after = Self.frame(interaction, manipulation, at: grown)
        #expect(before.current.scale == 0.02)
        #expect(after == before)
    }

    // MARK: - Test-first plan 3 and 4: what the commit keeps

    /// **Why the cheap fix is ruled out.** Pinning `settled` at gesture start would freeze the
    /// frame too — and take the stage off the fit for good, which ADR-028 forbids for a gesture
    /// that did nothing. The refit the fingers held off lands at finger-lift instead.
    @Test("an identity manipulation at a changing fit keeps following the fit")
    func anIdentityManipulationAtAChangingFitKeepsFollowingTheFit() throws {
        var interaction = StageInteraction()
        var manipulation = StageManipulation()
        interaction.beginManipulating(joining: manipulation, fitting: Self.fitA)
        manipulation.panBegan(at: .zero)

        #expect(Self.frame(interaction, manipulation, at: Self.fitB).current == Self.fitA)

        manipulation.panEnded()
        let finished = manipulation.finish(in: Self.viewport, touchesRemain: false)
        let gesture = try #require(finished)
        interaction.commit(gesture, fitting: Self.fitB, in: Self.viewport)

        #expect(interaction.isFollowingFit)
        #expect(Self.frame(interaction, manipulation, at: Self.fitB) == .settled(Self.fitB))
        #expect(interaction == StageInteraction(), "the commit left a frozen fit behind")
    }

    /// ADR-028: live and committed are the same number by construction. Committing against the
    /// fit at lift instead of the one the frames were drawn at would jump the stage as the
    /// fingers leave.
    @Test("a zoom at a changing fit commits from the frozen fit")
    func aZoomAtAChangingFitCommitsFromTheFrozenFit() throws {
        var interaction = StageInteraction()
        var manipulation = StageManipulation()
        Self.grabbedPinch(&interaction, &manipulation)
        let last = Self.frame(interaction, manipulation, at: Self.fitB).current

        let gesture = try Self.finished(&manipulation)
        interaction.commit(gesture, fitting: Self.fitB, in: Self.viewport)

        let atFitA = StageInteraction().transform(
            with: gesture, fitting: Self.fitA, in: Self.viewport
        )
        let atFitB = StageInteraction().transform(
            with: gesture, fitting: Self.fitB, in: Self.viewport
        )
        #expect(interaction.settled == last)
        #expect(interaction.settled == atFitA)
        #expect(interaction.settled != atFitB)

        var reference = StageInteraction()
        reference.commit(gesture, fitting: Self.fitA, in: Self.viewport)
        #expect(interaction == reference, "the commit left a frozen fit behind")
    }

    /// **The spoken zoom divides by the fit on screen, not the frozen one**, so the number does
    /// not jump at finger-lift: a 2× pinch begun at scale 1 and still held at a 0.5 fit reads
    /// 400 % both before and after the commit. Dividing by the frozen fit would read 200 % and
    /// then 400 % (`swift-code-reviewer`, mutant k).
    @Test("the spoken zoom does not jump at finger-lift when the fit changed")
    func theSpokenZoomDoesNotJumpAtFingerLift() throws {
        var interaction = StageInteraction()
        var manipulation = StageManipulation()
        Self.grabbedPinch(&interaction, &manipulation)
        let live = interaction.magnification(
            gesture: manipulation.gesture(in: Self.viewport), fitting: Self.fitB, in: Self.viewport
        )

        let gesture = try Self.finished(&manipulation)
        interaction.commit(gesture, fitting: Self.fitB, in: Self.viewport)

        #expect(live == 4)
        #expect(
            interaction.magnification(gesture: nil, fitting: Self.fitB, in: Self.viewport) == live
        )
    }

    // MARK: - Test-first plan 5: cancel clears it

    /// Observed through `Equatable` and the limits as well as the frame, because the frame alone
    /// cannot see it: with no gesture present the frozen fit is not honoured. The limits can —
    /// 50 / 1 at the frozen fit against 50 / 0.5 at the new one. **The frame assertion cannot
    /// fail** and is kept as documentation: since the next manipulation recaptures from a fresh
    /// tracker anyway, the clear is invisible to anything drawn, and `Equatable` plus the limits
    /// are its only discriminators.
    @Test("cancelling clears the frozen fit")
    func cancellingClearsTheFrozenFit() {
        var interaction = StageInteraction()
        var manipulation = StageManipulation()
        Self.grabbedPinch(&interaction, &manipulation)

        manipulation.cancelled()
        interaction.cancelManipulating()

        #expect(interaction == StageInteraction())
        #expect(Self.frame(interaction, manipulation, at: Self.fitB) == .settled(Self.fitB))
        #expect(
            interaction.magnificationLimits(fitting: Self.fitB)
                == StageInteraction().magnificationLimits(fitting: Self.fitB)
        )
    }

    // MARK: - Test-first plan 6: captured once, at the first channel

    /// The second channel's begin sees the grown fit — the coordinator passes whatever the
    /// snapshot holds — and must not recapture from it.
    @Test("two channels capture the fit once, at the first", arguments: FirstChannel.allCases)
    func twoChannelsCaptureTheFitOnceAtTheFirst(first: FirstChannel) {
        var interaction = StageInteraction()
        var manipulation = StageManipulation()

        interaction.beginManipulating(joining: manipulation, fitting: Self.fitA)
        switch first {
        case .pan:
            manipulation.panBegan(at: .zero)
            interaction.beginManipulating(joining: manipulation, fitting: Self.fitB)
            manipulation.pinchBegan(
                scale: 1,
                centroid: Self.grab,
                within: interaction.magnificationLimits(fitting: Self.fitB)
            )
        case .pinch:
            manipulation.pinchBegan(
                scale: 1,
                centroid: Self.grab,
                within: interaction.magnificationLimits(fitting: Self.fitA)
            )
            interaction.beginManipulating(joining: manipulation, fitting: Self.fitB)
            manipulation.panBegan(at: .zero)
        }
        manipulation.pinchChanged(to: 2)

        let atFitA = Self.frame(interaction, manipulation, at: Self.fitA)
        let atFitB = Self.frame(interaction, manipulation, at: Self.fitB)
        #expect(atFitB == atFitA)
        #expect(atFitB.bake == Self.fitA)
        #expect(
            interaction.magnificationLimits(fitting: Self.fitB)
                == interaction.magnificationLimits(fitting: Self.fitA)
        )
    }

    // MARK: - The lost teardown

    /// **The interaction outlives the tracker.** `StageInteraction` is `AppModel`'s and
    /// `StageManipulation` is the view's, so a view torn down mid-gesture — ADR-023's
    /// size-class rebuild, which is also a viewport change — can drop the tracker without a
    /// cancel ever reaching the coordinator. Whether UIKit delivers one is unmeasured, so the
    /// design must not depend on it: an at-rest frame ignores the stale fit, and the next
    /// manipulation's first channel recaptures because the tracker it joins is not live.
    @Test("a manipulation lost without a cancel does not freeze the next one")
    func aManipulationLostWithoutACancelDoesNotFreezeTheNextOne() {
        var interaction = StageInteraction()
        var lost = StageManipulation()
        Self.grabbedPinch(&interaction, &lost)

        var fresh = StageManipulation()
        #expect(Self.frame(interaction, fresh, at: Self.fitB) == .settled(Self.fitB))
        // `rendering`'s own guard answers the line above; these two are what the gesture check
        // in `fit(for:current:)` actually protects (`swift-code-reviewer`, mutant c).
        #expect(interaction.transform(with: nil, fitting: Self.fitB, in: Self.viewport) == Self.fitB)
        #expect(interaction.magnification(gesture: nil, fitting: Self.fitB, in: Self.viewport) == 1)

        interaction.beginManipulating(joining: fresh, fitting: Self.fitB)
        fresh.panBegan(at: .zero)
        #expect(Self.frame(interaction, fresh, at: Self.fitB).current == Self.fitB)
    }

    /// A new design arrives fitted; the frozen fit belongs to the old one.
    @Test("following the fit clears the frozen fit")
    func followingTheFitClearsTheFrozenFit() {
        var interaction = StageInteraction()
        var manipulation = StageManipulation()
        interaction.beginManipulating(joining: manipulation, fitting: Self.fitA)
        manipulation.panBegan(at: .zero)

        interaction.followFit()

        #expect(interaction == StageInteraction())
    }
}
