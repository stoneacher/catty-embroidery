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

    // MARK: - The numbers the coordinator hands the package

    /// **The single input this whole story exists to deliver**, and it was unasserted until the
    /// review deleted the pan's `.changed` arm and watched the suite stay green
    /// (`swift-code-reviewer`, I4). The story's headline defect was that lateral movement during a
    /// pinch was dropped; nothing would have noticed if it still were.
    @Test func aPanCommitsTheTranslationItLastReported() {
        let recording = Recording()
        let wiring = CatcherHarness.wired(recording)
        let coordinator = wiring.coordinator
        let view = wiring.view
        let pan = StubPan()
        let probe = CatcherHarness.fit.stagePoint(of: CatcherHarness.viewport.center)

        view.touchesArrived(1)
        pan.stubTranslation = CGPoint(x: 17, y: 9)
        pan.stubState = .began
        coordinator.panned(pan)
        pan.stubTranslation = CGPoint(x: 57, y: 29)
        pan.stubState = .changed
        coordinator.panned(pan)
        pan.stubState = .ended
        coordinator.panned(pan)
        view.touchesLeft(1)

        let settled = recording.interaction.settled
        #expect(settled != nil)
        let landed = settled?.viewPoint(of: probe)
        #expect(abs((landed?.x ?? 0) - (CatcherHarness.viewport.center.x + 57)) < 1e-6)
        #expect(abs((landed?.y ?? 0) - (CatcherHarness.viewport.center.y + 29)) < 1e-6)
    }

    /// **The threshold is included and never subtracted** — ADR-028 measured that subtraction (a
    /// 101 pt drag showing 91 and committing 101) and removed it, and the coordinator's comment
    /// calls re-basing to zero "the single most likely wrong reflex in this file". This is the
    /// case that can see it: a pan that begins and ends without ever reporting a change, where
    /// the beginning translation is the whole of the gesture.
    @Test func aPanThatNeverChangesStillCommitsItsBeginningTranslation() {
        let recording = Recording()
        let wiring = CatcherHarness.wired(recording)
        let coordinator = wiring.coordinator
        let view = wiring.view
        let pan = StubPan()
        let probe = CatcherHarness.fit.stagePoint(of: CatcherHarness.viewport.center)

        view.touchesArrived(1)
        pan.stubTranslation = CGPoint(x: 17, y: 9)
        pan.stubState = .began
        coordinator.panned(pan)
        pan.stubState = .ended
        coordinator.panned(pan)
        view.touchesLeft(1)

        let landed = recording.interaction.settled?.viewPoint(of: probe)
        #expect(landed != nil)
        #expect(abs((landed?.x ?? 0) - (CatcherHarness.viewport.center.x + 17)) < 1e-6)
        #expect(abs((landed?.y ?? 0) - (CatcherHarness.viewport.center.y + 9)) < 1e-6)
    }

    /// **The pinch anchors about the fingers, not about the viewport's centre** — the other half
    /// of "each finger keeps the stage point it grabbed", and also unasserted until the review
    /// replaced the centroid with `.zero` and the suite stayed green (I5). The old sequence used a
    /// centroid that happened to *be* the viewport centre, which is exactly the fallback
    /// `StageManipulation.gesture(in:)` uses when no anchor was ever set — so a coordinator
    /// passing nothing through was indistinguishable from one passing the right thing.
    @Test func aPinchCommitsAboutTheCentroidItWasGiven() {
        let recording = Recording()
        let wiring = CatcherHarness.wired(recording)
        let coordinator = wiring.coordinator
        let view = wiring.view
        let pinch = StubPinch()
        let centroid = ViewPoint(x: 100, y: 200)
        let grabbed = CatcherHarness.fit.stagePoint(of: centroid)

        view.touchesArrived(2)
        pinch.stubLocation = CGPoint(x: centroid.x, y: centroid.y)
        pinch.stubState = .began
        coordinator.pinched(pinch)
        pinch.scale = 2
        pinch.stubState = .changed
        coordinator.pinched(pinch)
        pinch.stubState = .ended
        coordinator.pinched(pinch)
        view.touchesLeft(2)

        let settled = recording.interaction.settled
        #expect(settled != nil)
        #expect(abs((settled?.scale ?? 0) - CatcherHarness.fit.scale * 2) < 1e-6)
        // The point under the fingers stayed under the fingers.
        let stayed = settled?.viewPoint(of: grabbed)
        #expect(abs((stayed?.x ?? 0) - centroid.x) < 1e-6)
        #expect(abs((stayed?.y ?? 0) - centroid.y) < 1e-6)
    }
}
