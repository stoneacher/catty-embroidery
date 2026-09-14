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

    /// Magnification limits wide enough never to bite — the clamping case has its own test in
    /// `StageManipulationTests`.
    private static let free = StageManipulation.unlimitedMagnification

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
        manipulation.pinchBegan(scale: 1, centroid: Self.viewport.center, within: Self.free)
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
        manipulation.pinchBegan(scale: 1, centroid: Self.viewport.center, within: Self.free)
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
        manipulation.pinchBegan(scale: 1, centroid: ViewPoint(x: 120, y: 260), within: Self.free)
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
        manipulation.pinchBegan(scale: 1, centroid: ViewPoint(x: 200, y: 300), within: Self.free)
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

    /// **The recogniser's threshold distance is part of the pan, and ADR-028 pins that.**
    ///
    /// US-307 tried subtracting it, measured a 101 pt drag committing 101 while showing 91, and
    /// **removed the subtraction entirely** — live and committed are then the same number by
    /// construction rather than two pieces of code agreeing, and the jump moves to pan *start*,
    /// where it reads as the drag catching. `StageGesture.panX`'s own doc says "including the
    /// recognizer's threshold distance. Not subtracted anywhere."
    ///
    /// This test exists because US-313a briefly reintroduced the subtraction — treating
    /// `panBegan(at:)`'s argument as an origin — on the reasoning that the tracker should not
    /// depend on the coordinator having zeroed the recogniser. That reasoning is fine and the
    /// conclusion was wrong: with a pinch live, dropping the threshold means the grabbed points
    /// stop tracking the fingers, which is the story's whole purpose. Found by `/codex-review`
    /// round 1.
    @Test("the pan carries the recogniser's threshold distance rather than subtracting it")
    func thePanCarriesTheRecognizerThreshold() throws {
        var manipulation = StageManipulation()
        manipulation.panBegan(at: ViewPoint(x: 12, y: 0))

        let atThreshold = try #require(manipulation.gesture(in: Self.viewport))
        #expect(atThreshold.panX == 12)

        manipulation.panChanged(to: ViewPoint(x: 22, y: 0))
        let moved = try #require(manipulation.gesture(in: Self.viewport))

        #expect(moved.panX == 22)
    }

    /// **A pinch can begin and end before the pan ever recognises.** UIKit starts a pan only
    /// after enough movement, so two fingers can land, pinch, and one lift — all with the pan
    /// still `.possible`. `Channel.absent` cannot tell "this recogniser never participated" from
    /// "this recogniser is still possible while a finger is down", so the tracker would commit,
    /// go `nil`, and then commit a second time when the remaining finger finally drags.
    ///
    /// The transform survives that (pinch-then-pan composes to the same place), but the gap
    /// between the two commits is a window where `gesture` is `nil` and rendering reports
    /// settled — so the raster can rebuild **with a finger still on the glass**, which is
    /// ADR-030 §7's inherited invariant. Found by `/codex-review` round 1.
    @Test("a pinch that ends while touches remain does not commit")
    func aPinchThatEndsWhileTouchesRemainDoesNotCommit() throws {
        var manipulation = StageManipulation()
        manipulation.pinchBegan(scale: 1, centroid: ViewPoint(x: 200, y: 250), within: Self.free)
        manipulation.pinchChanged(to: 2)
        manipulation.pinchEnded()

        #expect(manipulation.finish(in: Self.viewport, touchesRemain: true) == nil)
        // Still live, so no settled window opens while the finger is down.
        #expect(manipulation.gesture(in: Self.viewport) != nil)

        manipulation.panBegan(at: ViewPoint(x: 40, y: 0))
        manipulation.panEnded()
        let committed = manipulation.finish(in: Self.viewport, touchesRemain: false)

        #expect(committed?.magnification == 2)
        #expect(committed?.panX == 40)
    }

    /// A scale the recogniser should never send must not poison the manipulation. Zero is the
    /// case that persists: it would make `magnificationBase` zero and every later pinch zero too,
    /// pinning the stage at the minimum until the whole manipulation ends.
    @Test("a non-finite or non-positive scale is ignored rather than latched")
    func aNonFiniteScaleIsIgnored() throws {
        var manipulation = StageManipulation()
        manipulation.panBegan(at: .zero)
        manipulation.pinchBegan(scale: 1, centroid: ViewPoint(x: 200, y: 250), within: Self.free)
        manipulation.pinchChanged(to: 2)

        manipulation.pinchChanged(to: 0)
        manipulation.pinchChanged(to: .nan)
        manipulation.pinchChanged(to: .infinity)

        let held = try #require(manipulation.gesture(in: Self.viewport))
        #expect(held.magnification == 2)

        manipulation.pinchEnded()
        manipulation.pinchBegan(scale: 1, centroid: ViewPoint(x: 210, y: 250), within: Self.free)
        manipulation.pinchChanged(to: 3)
        let after = try #require(manipulation.gesture(in: Self.viewport))

        #expect(after.magnification == 6)
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
        manipulation.pinchBegan(scale: 1, centroid: Self.viewport.center, within: Self.free)
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
        manipulation.pinchBegan(scale: 1, centroid: Self.viewport.center, within: Self.free)
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
        manipulation.pinchBegan(scale: 1, centroid: ViewPoint(x: 120, y: 260), within: Self.free)
        manipulation.pinchChanged(to: 2)

        let gesture = try #require(manipulation.gesture(in: .zero))

        #expect(gesture.anchorUnitX == 0.5)
        #expect(gesture.anchorUnitY == 0.5)
    }
}
