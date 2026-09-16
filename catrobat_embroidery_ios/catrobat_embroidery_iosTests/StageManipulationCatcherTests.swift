@testable import catrobat_embroidery_ios
import StagePreview
import SwiftUI
import Testing
import UIKit

/// US-313b: the UIKit recogniser pair, and the coordinator that turns it into calls on
/// US-313a's pure tracker.
///
/// **The seam these tests drive was measured, not chosen.** The story's test plan proposes stub
/// recognisers "with a settable `state` via `import UIKit.UIGestureRecognizerSubclass`", and
/// flags the premise as one to verify at the red phase rather than take from the plan. Verified,
/// on a booted iPhone 17: the import compiles and `state` *is* assignable, and the assignment is
/// **silently swallowed** — `state` stays `.possible`, no action is ever dispatched,
/// `setTranslation(_:in:)` does nothing and `location(in:)` returns `.zero`. A stub built that
/// way would leave a coordinator switching on `state` taking no branch at all, and the tests
/// would be green for the wrong reason. What works, and what these use, is a subclass that
/// **overrides** the members; ObjC dynamic dispatch means a coordinator holding the base type
/// still sees the stub's values.
///
/// **Nothing here synthesises a touch**, because nothing can: `UITouch` has no public
/// initialiser. The touch *count* is therefore the tracking view's seam, and the tests drive it
/// directly — which is honest about what is being asserted, namely the coordinator's response to
/// a touch sequence rather than UIKit's delivery of one. The delivery is human check 1–3.
@MainActor
@Suite("Stage manipulation catcher")
struct StageManipulationCatcherTests {
    // MARK: - Stubs

    /// Overrides rather than assigns; see the suite comment.
    private final class StubPinch: UIPinchGestureRecognizer {
        var stubState: UIGestureRecognizer.State = .possible
        var stubLocation: CGPoint = .zero

        override var state: UIGestureRecognizer.State {
            get { stubState }
            set { stubState = newValue }
        }

        override func location(in _: UIView?) -> CGPoint {
            stubLocation
        }
    }

    private final class StubPan: UIPanGestureRecognizer {
        var stubState: UIGestureRecognizer.State = .possible
        var stubTranslation: CGPoint = .zero

        override var state: UIGestureRecognizer.State {
            get { stubState }
            set { stubState = newValue }
        }

        override func translation(in _: UIView?) -> CGPoint {
            stubTranslation
        }
    }

    private final class StubTap: UITapGestureRecognizer {
        var stubLocation: CGPoint = .zero

        override func location(in _: UIView?) -> CGPoint {
            stubLocation
        }
    }

    /// Holds what the bindings write, and counts the commits the coordinator reports.
    ///
    /// A local class per test rather than anything shared: these suites run in parallel.
    private final class Recording {
        var manipulation = StageManipulation()
        var interaction = StageInteraction()
        var commits = 0
        var taps: [ViewPoint] = []
    }

    private static let viewport = ViewSize(width: 400, height: 800)

    private static var fit: StageTransform {
        StageTransform.fitting(StageGeometry.box, in: viewport)
    }

    private static func snapshot(settlingAt progress: Double = 1) -> StageManipulationCatcher.Snapshot {
        StageManipulationCatcher.Snapshot(
            fitted: fit, viewport: viewport, settlingProgress: progress
        )
    }

    /// A coordinator wired to a recording, installed on a real tracking view.
    private static func wired(
        _ recording: Recording
    ) -> (StageManipulationCatcher.Coordinator, StageTouchTrackingView) {
        let coordinator = StageManipulationCatcher.Coordinator()
        let view = StageTouchTrackingView()
        coordinator.install(on: view)
        coordinator.update(
            snapshot: snapshot(),
            manipulation: Binding(
                get: { recording.manipulation }, set: { recording.manipulation = $0 }
            ),
            interaction: Binding(
                get: { recording.interaction }, set: { recording.interaction = $0 }
            ),
            onDoubleTap: { recording.taps.append($0) },
            onCommitted: { recording.commits += 1 }
        )
        return (coordinator, view)
    }

    // MARK: - AC1: what is installed

    /// **Four of these six assertions are the test.** "Installs three recognisers" passes on
    /// almost any implementation; the parameters are what make the pair behave like one gesture,
    /// and two of them are load-bearing in a way the story does not mention:
    ///
    /// - `cancelsTouchesInView = false`: at its default the tracking view stops receiving
    ///   `touchesEnded` the moment a recogniser recognises, so the touch count — the terminal
    ///   signal the commit depends on — would freeze above zero forever.
    /// - `delaysTouchesEnded = false`: at its default the tap recogniser holds the view's
    ///   `touchesEnded` for the double-tap interval, so every commit, and the settled re-bake
    ///   behind it, would arrive ~0.3 s after the fingers left the glass — landing squarely in
    ///   the tail device capture #2 is meant to attribute.
    @Test func theCatcherInstallsAPinchAPanAndADoubleTapRecognizer() {
        let coordinator = StageManipulationCatcher.Coordinator()

        #expect(coordinator.pan.minimumNumberOfTouches == 1)
        #expect(coordinator.pan.maximumNumberOfTouches == 2)
        #expect(coordinator.tap.numberOfTapsRequired == 2)

        let all: [UIGestureRecognizer] = [coordinator.pinch, coordinator.pan, coordinator.tap]
        #expect(all.allSatisfy { $0.delegate === coordinator })
        #expect(all.allSatisfy { !$0.cancelsTouchesInView })
        #expect(all.allSatisfy { !$0.delaysTouchesEnded })
    }

    @Test func installingAttachesTheThreeRecognizersToTheView() {
        let coordinator = StageManipulationCatcher.Coordinator()
        let view = StageTouchTrackingView()

        coordinator.install(on: view)

        #expect(view.gestureRecognizers?.count == 3)
    }

    // MARK: - AC2 and AC3: the delegate

    /// **Scoped to our own pair, which the story's wording does not require and which matters.**
    /// A blanket `true` satisfies "returns `true` for the pinch/pan pair" and also tells
    /// `NavigationStack`'s interactive-pop recogniser that it may run *simultaneously* with the
    /// pan — turning the story's "a one-finger pan keeps the existing conflict, which is the
    /// shipped state and not a regression" into a regression the story authorised.
    @Test func thePinchAndThePanRecognizeSimultaneously() {
        let coordinator = StageManipulationCatcher.Coordinator()
        let foreign = UIScreenEdgePanGestureRecognizer()

        #expect(coordinator.gestureRecognizer(
            coordinator.pinch, shouldRecognizeSimultaneouslyWith: coordinator.pan
        ))
        #expect(coordinator.gestureRecognizer(
            coordinator.pan, shouldRecognizeSimultaneouslyWith: coordinator.pinch
        ))
        #expect(!coordinator.gestureRecognizer(
            coordinator.pan, shouldRecognizeSimultaneouslyWith: foreign
        ))
    }

    /// **Restated from the story's wording, which is not assertable.** AC3 says the double tap
    /// "is not gated on the pan failing"; `require(toFail:)` is set-only and UIKit exposes no
    /// getter for a recogniser's failure requirements, so no test can read that back. What is
    /// assertable is our delegate's answer — that we impose no failure requirement in either
    /// direction, for any ordered pair. The substantive claim, that a pan is not delayed by the
    /// double-tap interval in the hand, is human check 3 and AC14's correction 3.
    @Test func theDoubleTapIsNotGatedOnThePanFailing() {
        let coordinator = StageManipulationCatcher.Coordinator()
        let all: [UIGestureRecognizer] = [coordinator.pinch, coordinator.pan, coordinator.tap]

        for one in all {
            for other in all where one !== other {
                #expect(!coordinator.gestureRecognizer(one, shouldRequireFailureOf: other))
                #expect(!coordinator.gestureRecognizer(one, shouldBeRequiredToFailBy: other))
            }
        }
    }

    // MARK: - AC4: one manipulation, one commit

    @Test func aRecognizerActionSequenceDrivesTheTrackerAndCommitsOnce() {
        let recording = Recording()
        let (coordinator, view) = Self.wired(recording)
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
        #expect(recording.manipulation.gesture(in: Self.viewport) == nil)
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
        let (coordinator, view) = Self.wired(recording)
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
        let (coordinator, view) = Self.wired(recording)
        let pinch = StubPinch()
        let bounds = StageZoomBounds(fitting: Self.fit, including: Self.fit.scale)

        view.touchesArrived(2)
        pinch.stubLocation = CGPoint(x: 200, y: 400)
        pinch.stubState = .began
        coordinator.pinched(pinch)
        pinch.scale = 5000
        pinch.stubState = .changed
        coordinator.pinched(pinch)

        let live = recording.manipulation.gesture(in: Self.viewport)
        #expect(live != nil)
        #expect((live?.magnification ?? 0) * Self.fit.scale <= bounds.maximum * (1 + 1e-9))
    }

    // MARK: - AC5: cancellation

    /// The app-level companion to US-313a's AC8. `@GestureState` clears itself when the system
    /// takes the touches away; a coordinator does not, and missing it leaves the stage
    /// permanently live — `canUseRaster` false forever, the design coarse forever.
    @Test func aCancelledRecognizerLeavesNoLiveState() {
        let recording = Recording()
        let (coordinator, view) = Self.wired(recording)
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
        #expect(recording.manipulation.gesture(in: Self.viewport) == nil)
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
        let (coordinator, view) = Self.wired(recording)
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
        let (coordinator, view) = Self.wired(recording)
        let pinch = StubPinch()

        view.touchesArrived(2)
        pinch.stubState = .began
        coordinator.pinched(pinch)
        pinch.scale = 3
        pinch.stubState = .changed
        coordinator.pinched(pinch)
        view.touchesCancelledByTheSystem()

        #expect(recording.commits == 0)
        #expect(!recording.manipulation.isLive)
        #expect(recording.interaction.settled == nil)
    }

    // MARK: - The double tap

    /// The coordinator's half of AC6: the tapped point reaches the view, in view coordinates.
    /// What the view then does with it — fit ↔ 2× about that point — is asserted through the
    /// hosted stage in `StageViewWiringTests`, because the animation belongs to SwiftUI.
    @Test func theDoubleTapHandsOutTheTappedPoint() {
        let recording = Recording()
        let (coordinator, _) = Self.wired(recording)
        let tap = StubTap()
        tap.stubLocation = CGPoint(x: 120, y: 380)

        coordinator.doubleTapped(tap)

        #expect(recording.taps.count == 1)
        #expect(recording.taps.first == ViewPoint(x: 120, y: 380))
    }

    // MARK: - AC7: the catcher is not an accessibility element

    /// **Asserted on the view's own flags, deliberately not by walking a published accessibility
    /// tree.** US-307 shipped such a test, watched it pass locally and fail unreproducibly on
    /// CI, and deleted it; the note is at the foot of `StageViewWiringTests`. AC8 — that the
    /// stage is still exactly *one* element — is a human check with the Accessibility Inspector
    /// for the same reason.
    ///
    /// Honest about which line does the work: `isAccessibilityElement == false` is the default
    /// for a plain `UIView`, so that expectation cannot fail against a correct implementation —
    /// it guards the future edit that sets it `true` to make the catcher "tappable", which a
    /// recogniser does not require. `accessibilityElementsHidden` is not a default, and it hides
    /// *descendants*, so on today's leaf view it too is a guard for a subview that does not yet
    /// exist. Both are worth having; neither is worth overclaiming.
    @Test func theCatcherIsNotAnAccessibilityElement() {
        let view = StageTouchTrackingView()

        #expect(!view.isAccessibilityElement)
        #expect(view.accessibilityElementsHidden)
    }

    // MARK: - What `updateUIView` must never do

    /// The catcher is built **inside** the `SettlingProgress` shim, so its update runs on every
    /// animation frame, every run batch and every touch move. Re-creating or re-installing a
    /// recogniser there cancels the gesture in flight — the single most dangerous thing that
    /// method could do, and invisible in a screenshot.
    @Test func updatingDoesNotReinstallTheRecognizers() {
        let recording = Recording()
        let (coordinator, view) = Self.wired(recording)
        let installed = view.gestureRecognizers ?? []

        for progress in [0.0, 0.25, 0.5, 1.0] {
            coordinator.update(
                snapshot: Self.snapshot(settlingAt: progress),
                manipulation: Binding(
                    get: { recording.manipulation }, set: { recording.manipulation = $0 }
                ),
                interaction: Binding(
                    get: { recording.interaction }, set: { recording.interaction = $0 }
                ),
                onDoubleTap: { _ in },
                onCommitted: nil
            )
        }

        #expect(view.gestureRecognizers?.count == 3)
        #expect(zip(view.gestureRecognizers ?? [], installed).allSatisfy { $0 === $1 })
        #expect(coordinator.snapshot.settlingProgress == 1.0)
    }

    /// **The app-level survivor of ADR-028's Codex round 8**, which today has no test at all.
    /// The model's settling progress jumps to 1 the instant `withAnimation` runs; only the
    /// shim's closure holds the interpolated value. A catcher constructed outside the shim would
    /// interrupt an animation at its *destination*, snapping the stage from what the user can
    /// see to where it was heading. This proves the interpolated value reaches the coordinator
    /// through SwiftUI; the per-frame cadence stays a visual check.
    @Test func theCatcherSeesTheShimsInterpolatedProgress() {
        let recording = Recording()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let hosted = SettlingProgress(progress: 0.5) { animated in
            StageManipulationCatcher(
                snapshot: StageManipulationCatcher.Snapshot(
                    fitted: Self.fit, viewport: Self.viewport, settlingProgress: animated
                ),
                manipulation: Binding(
                    get: { recording.manipulation }, set: { recording.manipulation = $0 }
                ),
                interaction: Binding(
                    get: { recording.interaction }, set: { recording.interaction = $0 }
                ),
                onDoubleTap: { _ in },
                onCommitted: nil
            )
        }
        let controller = UIHostingController(rootView: hosted)
        window.rootViewController = controller
        window.isHidden = false
        controller.view.frame = window.bounds
        window.layoutIfNeeded()
        controller.view.layoutIfNeeded()

        let coordinator = Self.coordinator(in: controller.view)
        #expect(coordinator != nil, "the catcher never reached the hierarchy")
        #expect(coordinator?.snapshot.settlingProgress == 0.5)
    }

    /// Finds the coordinator the way a hosted test must: through the recogniser it is the
    /// delegate of. A `UIView` walk, not an accessibility-tree walk — deterministic, and
    /// unaffected by whether the accessibility server has engaged.
    private static func coordinator(in root: UIView) -> StageManipulationCatcher.Coordinator? {
        if let found = root.gestureRecognizers?
            .compactMap({ $0.delegate as? StageManipulationCatcher.Coordinator }).first
        {
            return found
        }
        for subview in root.subviews {
            if let found = coordinator(in: subview) {
                return found
            }
        }
        return nil
    }
}
