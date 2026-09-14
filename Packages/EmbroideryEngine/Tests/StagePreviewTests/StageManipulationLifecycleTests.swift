import StagePreview
import Testing

/// **The two-channel lifecycle** — when a manipulation is live, when it commits, and what
/// happens when the system takes the touches away.
///
/// Split from `StageManipulationTests`, which holds the geometry. The seam is real (one half is
/// arithmetic about where fingers are, the other is about recogniser states) and the split was
/// *forced* by SwiftLint's 400-line file limit under `--strict`, exactly as it was for
/// `StitchDrawPlanCoarseningRuleTests`.
///
/// ADR-028 claims the single commit "deletes entirely" a state machine of per-channel end
/// bookkeeping. Two UIKit recognisers have independent lifecycles, so it comes back — and these
/// are the tests that make it a value under `swift test` rather than four pieces of `@State` in
/// a view, which is the whole argument for it living here.
@Suite("Stage manipulation lifecycle")
struct StageManipulationLifecycleTests {
    private static let viewport = ViewSize(width: 390, height: 500)

    private static var fit: StageTransform {
        StageTransform.fitting(StageGeometry.box, in: viewport)
    }

    /// Where the stage lands for a gesture, from a fresh interaction following the fit.
    private static func transform(for gesture: StageGesture) -> StageTransform {
        StageInteraction().transform(with: gesture, fitting: fit, in: viewport)
    }

    // MARK: - One manipulation, one commit

    /// **The rule two recognisers make ambiguous.** A pinch ends when a finger lifts; a pan with
    /// `maximumNumberOfTouches = 2` carries on with the other. Committing at the *first* channel
    /// end would write `settled` twice for one manipulation — and therefore re-bake a
    /// 50 000-stitch prefix twice, back to back, at finger-lift, which is exactly where ADR-030
    /// says the tail already lives.
    @Test("ending one channel while the other is live produces no commit value")
    func endingOneChannelWhileTheOtherIsLiveProducesNoCommitValue() {
        var manipulation = StageManipulation()
        manipulation.panBegan(at: .zero)
        manipulation.pinchBegan(scale: 1, centroid: Self.viewport.center)
        manipulation.panChanged(to: ViewPoint(x: 30, y: 10))
        manipulation.pinchChanged(to: 1.5)

        manipulation.pinchEnded()

        #expect(manipulation.finish(in: Self.viewport) == nil)
        #expect(manipulation.gesture(in: Self.viewport) != nil)
    }

    /// This is the assertion ADR-028 records as unobtainable: its
    /// `onlyTheFinalCumulativeValueIsApplied` collapsed to `once == once`, because "applied
    /// exactly once" was a fact about a SwiftUI view. Moving the decision into the package is
    /// what makes it a fact about a value.
    @Test("a manipulation yields exactly one commit value")
    func aManipulationYieldsExactlyOneCommitValue() {
        var manipulation = StageManipulation()
        manipulation.panBegan(at: .zero)
        manipulation.pinchBegan(scale: 1, centroid: Self.viewport.center)
        manipulation.panChanged(to: ViewPoint(x: 30, y: 10))
        manipulation.pinchChanged(to: 1.5)

        manipulation.pinchEnded()
        manipulation.panEnded()

        #expect(manipulation.finish(in: Self.viewport) != nil)
        #expect(manipulation.finish(in: Self.viewport) == nil)
        #expect(manipulation.gesture(in: Self.viewport) == nil)
    }

    /// ADR-028's "live and committed are the same number by construction", preserved: what the
    /// last frame drew is what gets committed, so the stage cannot shift at finger-lift.
    @Test("the committed value is the last live value")
    func theCommittedValueIsTheLastLiveValue() throws {
        var manipulation = StageManipulation()
        manipulation.panBegan(at: .zero)
        manipulation.pinchBegan(scale: 1, centroid: ViewPoint(x: 120, y: 260))
        manipulation.panChanged(to: ViewPoint(x: -14, y: 62))
        manipulation.pinchChanged(to: 2.25)

        let live = try #require(manipulation.gesture(in: Self.viewport))
        manipulation.pinchEnded()
        manipulation.panEnded()

        #expect(manipulation.finish(in: Self.viewport) == live)
    }

    /// A finger lifts, the other keeps dragging. The magnification must stay where the pinch
    /// left it: dropping it snaps the stage back toward 1× in the middle of a manipulation the
    /// user has not finished.
    @Test("a latched magnification survives the pinch ending")
    func aLatchedMagnificationSurvivesThePinchEnding() throws {
        var manipulation = StageManipulation()
        manipulation.panBegan(at: .zero)
        manipulation.pinchBegan(scale: 1, centroid: ViewPoint(x: 200, y: 300))
        manipulation.pinchChanged(to: 2)
        manipulation.panChanged(to: ViewPoint(x: 40, y: 15))

        let before = try #require(manipulation.gesture(in: Self.viewport))
        manipulation.pinchEnded()
        let after = try #require(manipulation.gesture(in: Self.viewport))

        // Continuous across the channel end — the frame does not move because a finger left.
        #expect(Self.transform(for: after) == Self.transform(for: before))

        manipulation.panChanged(to: ViewPoint(x: 80, y: 15))
        let stillPanning = try #require(manipulation.gesture(in: Self.viewport))

        #expect(stillPanning.magnification == 2)
    }

    /// **A pan that begins with a non-zero translation contributes nothing until it moves.**
    ///
    /// US-313b's coordinator will call `setTranslation(.zero, in:)` at `.began`, so in the
    /// shipped path this value is zero — which is exactly why the tracker should not depend on
    /// it. The parameter is named `at:` because it is an *origin*, and the untested half of the
    /// system (a UIKit coordinator) should not be the thing that has to remember that.
    @Test("a pan that begins away from zero contributes nothing until it moves")
    func aPanThatBeginsAwayFromZeroContributesNothing() throws {
        var manipulation = StageManipulation()
        manipulation.panBegan(at: ViewPoint(x: 5, y: -8))

        let resting = try #require(manipulation.gesture(in: Self.viewport))
        #expect(resting.isIdentity)

        manipulation.panChanged(to: ViewPoint(x: 25, y: 12))
        let moved = try #require(manipulation.gesture(in: Self.viewport))

        #expect(moved.panX == 20)
        #expect(moved.panY == 20)
    }

    // MARK: - Lifecycle failures

    /// **The regression this approach risks and `@GestureState` cannot have.** SwiftUI clears a
    /// `@GestureState` when the system cancels a gesture; a UIKit coordinator does not. Miss
    /// `.cancelled` and an incoming call leaves the stage permanently live — `canUseRaster` false
    /// forever, the design coarse forever, and the settled raster never rebuilt.
    @Test("a cancelled manipulation commits nothing and clears liveness")
    func aCancelledManipulationCommitsNothingAndClearsLiveness() {
        var manipulation = StageManipulation()
        manipulation.panBegan(at: .zero)
        manipulation.pinchBegan(scale: 1, centroid: Self.viewport.center)
        manipulation.panChanged(to: ViewPoint(x: 30, y: 10))
        manipulation.pinchChanged(to: 1.5)

        manipulation.cancelled()

        #expect(manipulation.gesture(in: Self.viewport) == nil)
        #expect(manipulation.finish(in: Self.viewport) == nil)
    }

    /// A cancelled manipulation must not poison the next one.
    @Test("a manipulation after a cancellation starts from nothing")
    func aManipulationAfterACancellationStartsFromNothing() throws {
        var manipulation = StageManipulation()
        manipulation.panBegan(at: .zero)
        manipulation.panChanged(to: ViewPoint(x: 120, y: 90))
        manipulation.cancelled()

        manipulation.panBegan(at: .zero)
        let gesture = try #require(manipulation.gesture(in: Self.viewport))

        #expect(gesture.isIdentity)
    }

    /// Four review rounds paid for this in `StageInteraction`, in four different spellings; the
    /// same question is now asked one layer further out and must have the same answer.
    /// A pinch back to exactly 1× and a pan back to its origin are **still a live manipulation**
    /// — the fingers are down.
    @Test("liveness is presence, not magnitude")
    func presenceNotMagnitudeDecidesLiveness() throws {
        var manipulation = StageManipulation()
        manipulation.panBegan(at: .zero)
        manipulation.pinchBegan(scale: 1, centroid: Self.viewport.center)
        manipulation.pinchChanged(to: 2)
        manipulation.panChanged(to: ViewPoint(x: 40, y: 40))

        manipulation.pinchChanged(to: 1)
        manipulation.panChanged(to: .zero)

        let gesture = try #require(manipulation.gesture(in: Self.viewport))

        #expect(gesture.isIdentity)
    }

    /// Totality before layout settles, matching `StageTransform.fitting`'s house rule: a
    /// viewport of zero must not produce a NaN anchor that then propagates into the transform.
    @Test("a zero viewport anchors at the centre")
    func aZeroViewportAnchorsAtTheCentre() throws {
        var manipulation = StageManipulation()
        manipulation.pinchBegan(scale: 1, centroid: ViewPoint(x: 120, y: 260))
        manipulation.pinchChanged(to: 2)

        let gesture = try #require(manipulation.gesture(in: .zero))

        #expect(gesture.anchorUnitX == 0.5)
        #expect(gesture.anchorUnitY == 0.5)
    }
}
