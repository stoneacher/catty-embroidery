@testable import catrobat_embroidery_ios
import StagePreview
import SwiftUI
import Testing
import UIKit

/// The coordinator's lifecycle: when a manipulation commits, when it must not, and what a
/// cancel leaves behind.
///
/// **Split from `StageManipulationCatcherTests` at SwiftLint's 400-line limit**, and the seam is
/// a real one: that suite asks what the catcher *is* — which recognisers, which parameters,
/// which delegate answers — and this one asks what it *does* over a sequence of events. The two
/// overlap nowhere.
///
/// Two of these tests exist because the story's three lifecycle rules are individually right and
/// jointly incomplete; `aPinchThatEndsLastWithThePanNeverBegunStillCommits` is the one that
/// matters, and `nothingAfterACancelActsUntilTheGlassIsClear` is its cancellation twin.
@MainActor
@Suite("Stage manipulation lifecycle")
struct StageCatcherLifecycleTests {
    // MARK: - AC4: one manipulation, one commit

    @Test func aRecognizerActionSequenceDrivesTheTrackerAndCommitsOnce() {
        let recording = Recording()
        let wiring = CatcherHarness.wired(recording)
        let coordinator = wiring.coordinator
        let view = wiring.view
        let pinch = StubPinch()
        let pan = StubPan()

        view.touchesArrived(2)
        pinch.stubLocation = CGPoint(x: 200, y: 400)
        pinch.stubState = .began
        coordinator.pinched(pinch)
        pan.stubState = .began
        coordinator.panned(pan)

        for step in 1 ... 2 {
            pinch.scale = 1 + 0.5 * Double(step)
            pinch.stubState = .changed
            coordinator.pinched(pinch)
            pan.stubTranslation = CGPoint(x: 10 * step, y: 5 * step)
            pan.stubState = .changed
            coordinator.panned(pan)
            #expect(recording.commits == 0, "a commit landed mid-manipulation")
            #expect(recording.manipulation.isLive)
        }

        pinch.stubState = .ended
        coordinator.pinched(pinch)
        #expect(recording.commits == 0, "the pinch ending is not the manipulation ending")
        pan.stubState = .ended
        coordinator.panned(pan)
        view.touchesLeft(2)

        #expect(recording.commits == 1)
        #expect(recording.interaction.settled != nil)
        #expect(!recording.manipulation.isLive)
        #expect(recording.manipulation.gesture(in: CatcherHarness.viewport) == nil)
    }

    /// **The hole in the story's lifecycle rules, which are individually right and jointly
    /// incomplete.** Two fingers land, the pinch begins, and the user pinches without moving the
    /// centroid past the pan's slop — so the pan stays `.possible` and never sends an action.
    /// One finger lifts: the pinch ends, touches remain, correctly no commit. The last finger
    /// lifts: **no action method runs at all**, because the only recogniser that recognised has
    /// already ended. The commit never fires, the manipulation stays live forever,
    /// `canUseRaster` stays false and the design stays coarse — the exact catastrophe the
    /// story's rule 3 was written to prevent, arriving through rule 2's door.
    ///
    /// The fix is that the touch count is itself a terminal signal, so the settle is attempted
    /// from every one of them; `finish(in:touchesRemain:)` is idempotent, so attempting twice
    /// costs nothing.
    @Test func aPinchThatEndsLastWithThePanNeverBegunStillCommits() {
        let recording = Recording()
        let wiring = CatcherHarness.wired(recording)
        let coordinator = wiring.coordinator
        let view = wiring.view
        let pinch = StubPinch()

        view.touchesArrived(2)
        pinch.stubLocation = CGPoint(x: 150, y: 300)
        pinch.stubState = .began
        coordinator.pinched(pinch)
        pinch.scale = 2
        pinch.stubState = .changed
        coordinator.pinched(pinch)

        pinch.stubState = .ended
        coordinator.pinched(pinch)
        view.touchesLeft(1)
        #expect(recording.commits == 0, "a finger is still down")

        view.touchesLeft(1)

        #expect(recording.commits == 1)
        #expect(!recording.manipulation.isLive)
        #expect(recording.interaction.settled != nil)
    }

    /// The pinch is clamped into the range the transform will actually apply, which is what
    /// makes `StageManipulation`'s rebase exact rather than approximately right. Passing
    /// `unlimitedMagnification` instead compiles, looks fine, and breaks the rebase at the
    /// bounds — which a fitted design reaches in a few pinches.
    @Test func theCoordinatorPinchesWithinTheInteractionsLimits() {
        let recording = Recording()
        let wiring = CatcherHarness.wired(recording)
        let coordinator = wiring.coordinator
        let view = wiring.view
        let pinch = StubPinch()
        let bounds = StageZoomBounds(fitting: CatcherHarness.fit, including: CatcherHarness.fit.scale)

        view.touchesArrived(2)
        pinch.stubLocation = CGPoint(x: 200, y: 400)
        pinch.stubState = .began
        coordinator.pinched(pinch)
        pinch.scale = 5000
        pinch.stubState = .changed
        coordinator.pinched(pinch)

        let live = recording.manipulation.gesture(in: CatcherHarness.viewport)
        #expect(live != nil)
        // **Both sides.** The upper half alone is satisfied by a magnification of 1 — that is, by
        // a coordinator that dropped the pinch entirely — so the lower half is what says the
        // pinch was applied and then clamped rather than ignored (`swift-code-reviewer`, S2).
        let scaled = (live?.magnification ?? 0) * CatcherHarness.fit.scale
        #expect(scaled <= bounds.maximum * (1 + 1e-9))
        #expect(scaled >= bounds.maximum * (1 - 1e-9))
    }

    // MARK: - AC5: cancellation

    /// The app-level companion to US-313a's AC8. `@GestureState` clears itself when the system
    /// takes the touches away; a coordinator does not, and missing it leaves the stage
    /// permanently live — `canUseRaster` false forever, the design coarse forever.
    @Test func aCancelledRecognizerLeavesNoLiveState() {
        let recording = Recording()
        let wiring = CatcherHarness.wired(recording)
        let coordinator = wiring.coordinator
        let view = wiring.view
        let pinch = StubPinch()

        view.touchesArrived(2)
        pinch.stubState = .began
        coordinator.pinched(pinch)
        pinch.scale = 2
        pinch.stubState = .changed
        coordinator.pinched(pinch)
        pinch.stubState = .cancelled
        coordinator.pinched(pinch)

        #expect(recording.commits == 0, "a cancelled manipulation must commit nothing")
        #expect(!recording.manipulation.isLive)
        #expect(recording.manipulation.gesture(in: CatcherHarness.viewport) == nil)
        #expect(recording.interaction.settled == nil)
    }

    /// **The companion the story lacks.** `cancelled()` resets the whole tracker, so a pan that
    /// is still physically in flight has no channel to report into — harmless on its own. But a
    /// second finger landing afterwards re-arms the tracker through `pinchBegan`, while the pan
    /// channel stays dead for the rest of the touch sequence: the stage would pinch and refuse
    /// to pan. Suppressing every action until the glass is clear makes "the system took the
    /// touches away" mean one thing rather than two.
    @Test func nothingAfterACancelActsUntilTheGlassIsClear() {
        let recording = Recording()
        let wiring = CatcherHarness.wired(recording)
        let coordinator = wiring.coordinator
        let view = wiring.view
        let pinch = StubPinch()
        let pan = StubPan()

        view.touchesArrived(2)
        pinch.stubState = .began
        coordinator.pinched(pinch)
        pinch.stubState = .cancelled
        coordinator.pinched(pinch)

        // The pan was mid-flight and UIKit keeps sending it until the fingers leave.
        pan.stubState = .changed
        coordinator.panned(pan)
        pan.stubState = .ended
        coordinator.panned(pan)
        // A second pinch on the same, already-cancelled touch sequence.
        pinch.stubState = .began
        coordinator.pinched(pinch)

        #expect(recording.commits == 0)
        #expect(!recording.manipulation.isLive)

        // Once the glass is clear, a fresh manipulation works normally.
        view.touchesLeft(2)
        view.touchesArrived(2)
        pinch.stubState = .began
        coordinator.pinched(pinch)

        #expect(recording.manipulation.isLive, "a new touch sequence must not stay suppressed")
    }

    /// A system cancel delivered to the *view* rather than to a recogniser — the same event
    /// from the other side. It must not be mistaken for a clean end, which would commit.
    @Test func aViewLevelCancelCommitsNothing() {
        let recording = Recording()
        let wiring = CatcherHarness.wired(recording)
        let coordinator = wiring.coordinator
        let view = wiring.view
        let pinch = StubPinch()

        view.touchesArrived(2)
        pinch.stubState = .began
        coordinator.pinched(pinch)
        pinch.scale = 3
        pinch.stubState = .changed
        coordinator.pinched(pinch)
        // **The production path**, count and all: `touchesCancelled(_:with:)` can only hand this
        // method a count, because `UITouch` has no public initialiser.
        view.touchesCancelledByTheSystem(count: 2)

        #expect(recording.commits == 0)
        #expect(!recording.manipulation.isLive)
        #expect(recording.interaction.settled == nil)

        // **And the stage is usable again immediately.** The first version of this file decremented
        // the count silently inside the override and reported only the cancel, so on the ordinary
        // path — the system taking every touch — nothing ever observed the count reach zero, the
        // coordinator's suppression flag stayed set, and the **whole next touch sequence was
        // swallowed**: no pinch, no pan, no double tap. The old test could not see it because it
        // called the notification helper directly rather than the path UIKit uses
        // (`swift-code-reviewer`, C1).
        view.touchesArrived(2)
        pinch.stubState = .began
        coordinator.pinched(pinch)

        #expect(recording.manipulation.isLive, "a cancel left the next gesture suppressed")
    }

    /// A cancel that takes only *some* of the touches leaves the rest suppressed, which is the
    /// other half of "until the glass is clear" — the fingers still down belong to a sequence the
    /// system has already disowned.
    @Test func aPartialCancelStaysSuppressedWhileAFingerRemains() {
        let recording = Recording()
        let wiring = CatcherHarness.wired(recording)
        let coordinator = wiring.coordinator
        let view = wiring.view
        let pinch = StubPinch()

        view.touchesArrived(2)
        pinch.stubState = .began
        coordinator.pinched(pinch)
        view.touchesCancelledByTheSystem(count: 1)

        pinch.stubState = .began
        coordinator.pinched(pinch)
        #expect(!recording.manipulation.isLive, "a finger from the cancelled sequence is still down")

        view.touchesLeft(1)
        view.touchesArrived(2)
        pinch.stubState = .began
        coordinator.pinched(pinch)
        #expect(recording.manipulation.isLive)
    }

    /// S3: the double tap is suppressed too, and by the same flag. Without this, removing its
    /// guard is a green mutation.
    @Test func aDoubleTapDuringACancelledSequenceIsIgnored() {
        let recording = Recording()
        let wiring = CatcherHarness.wired(recording)
        let coordinator = wiring.coordinator
        let view = wiring.view
        let pinch = StubPinch()
        let tap = StubTap()

        view.touchesArrived(2)
        pinch.stubState = .began
        coordinator.pinched(pinch)
        pinch.stubState = .cancelled
        coordinator.pinched(pinch)
        coordinator.doubleTapped(tap)

        #expect(recording.taps.isEmpty, "a tap on a disowned touch sequence must not toggle")

        view.touchesLeft(2)
        coordinator.doubleTapped(tap)
        #expect(recording.taps.count == 1)
    }

    /// **Both terminal signals are independent, and the reverse delivery order proves it.**
    ///
    /// Every other test here delivers the recogniser's `.ended` before the touches lift, so the
    /// zero-count callback is what commits and the `.ended` arm's own `settleIfFinished()` can be
    /// deleted with the suite green (`/codex-review` round 1, finding 5). In this order the count
    /// reaches zero while the pinch channel is still active — `finish` correctly returns `nil` —
    /// and nothing but the `.ended` arm is left to retry. ADR-031 says the order must not matter;
    /// until now only one order was ever exercised.
    @Test func theTouchesCanLiftBeforeTheRecognizerEndsAndStillCommitOnce() {
        let recording = Recording()
        let wiring = CatcherHarness.wired(recording)
        let coordinator = wiring.coordinator
        let view = wiring.view
        let pinch = StubPinch()

        view.touchesArrived(2)
        pinch.stubLocation = CGPoint(x: 150, y: 300)
        pinch.stubState = .began
        coordinator.pinched(pinch)
        pinch.scale = 2
        pinch.stubState = .changed
        coordinator.pinched(pinch)

        // The glass clears first, while the pinch has not yet reported its end.
        view.touchesLeft(2)
        #expect(recording.commits == 0, "a channel is still active")

        pinch.stubState = .ended
        coordinator.pinched(pinch)

        #expect(recording.commits == 1)
        #expect(!recording.manipulation.isLive)
        #expect(recording.interaction.settled != nil)
    }

    /// **The limits are read *after* the interrupt, and the order is observable.**
    ///
    /// `beginManipulating` ends any fit animation at its *visible* progress, which moves the
    /// baseline; a magnification range computed before it is computed against the animation's
    /// **destination** while the user pinches against what is on screen. The tracker's clamped
    /// factor then stops matching the one `StageTransform.pinched` applies, and the next re-anchor
    /// jumps — `/codex-review` round 2 on US-313a found that in the package, and nothing guarded
    /// the coordinator's ordering until round 1 of this story's review pointed out that no test
    /// begins a pinch during an animation (finding 4).
    @Test func thePinchLimitsComeFromWhatIsOnScreenNotFromTheAnimationsDestination() throws {
        let recording = Recording()
        let fit = CatcherHarness.fit
        var interaction = StageInteraction()
        interaction.commit(
            StageGesture(magnification: 8), fitting: fit, in: CatcherHarness.viewport
        )
        // Assigned first: `#require` captures its expression in a closure, where `interaction`
        // would be immutable and `beginSettling` is mutating.
        let settling = interaction.beginSettling(fitting: fit)
        #expect(settling != nil, "there must be something to animate")
        recording.interaction = interaction
        // What the user can see halfway through the animation back to the fit.
        let visible = interaction.baseline(fitting: fit, settlingAt: 0.5)

        let wiring = CatcherHarness.wired(recording, settlingAt: 0.5)
        let pinch = StubPinch()
        wiring.view.touchesArrived(2)
        pinch.stubLocation = CGPoint(x: 200, y: 400)
        pinch.stubState = .began
        wiring.coordinator.pinched(pinch)
        pinch.scale = 5_000
        pinch.stubState = .changed
        wiring.coordinator.pinched(pinch)

        let live = try #require(recording.manipulation.gesture(in: CatcherHarness.viewport))
        let bounds = StageZoomBounds(fitting: fit, including: visible.scale)
        let expected = bounds.maximum / visible.scale
        #expect(abs(live.magnification - expected) < 1e-6)
        // …and that really is a different number from the one the destination would give, or
        // this test would pass against the defect it names.
        let fromDestination = StageZoomBounds(fitting: fit, including: fit.scale).maximum / fit.scale
        #expect(abs(expected - fromDestination) > 1e-6)
    }
}
