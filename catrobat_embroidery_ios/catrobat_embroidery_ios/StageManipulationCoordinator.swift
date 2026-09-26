import StagePreview
import SwiftUI
import UIKit

extension StageManipulationCatcher {
    /// Turns three recognisers' callbacks into calls on the package, and answers the one
    /// question two recognisers make ambiguous: when is *the* gesture over?
    ///
    /// **Three lifecycle rules, and the third is the one this repo would otherwise ship
    /// broken.**
    ///
    /// 1. **Liveness is asked of the recognisers, never inferred from values.** Nothing here
    ///    compares a transform or a magnification to decide whether something is happening;
    ///    `state` drives `StageManipulation`'s channels and `isLive` is its answer. ADR-028's
    ///    review found the value-comparing version of this question wrong in four spellings.
    /// 2. **The commit fires when the last channel ends** — `finish(in:touchesRemain:)` returns
    ///    non-`nil` exactly once — because committing at the first end would write
    ///    `StageInteraction.settled` twice for one manipulation, and so re-bake a
    ///    50 000-stitch prefix twice back to back at finger-lift, exactly where ADR-030 puts
    ///    the residual tail.
    /// 3. **`.cancelled` and `.failed` are handled, and then everything is suppressed until the
    ///    glass is clear.** `@GestureState` clears itself for a system-cancelled gesture; a
    ///    coordinator does not, and missing it leaves the stage permanently live. Suppression
    ///    is the half the story does not contain: `cancelled()` resets the tracker, so a second
    ///    finger landing on the *same* cancelled touch sequence would re-arm the pinch channel
    ///    while the pan channel stayed dead — the stage would pinch and refuse to pan.
    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let pinch = UIPinchGestureRecognizer()
        let pan = UIPanGestureRecognizer()
        let tap = UITapGestureRecognizer()

        private(set) var snapshot = Snapshot.placeholder
        private var manipulation: Binding<StageManipulation>?
        private var interaction: Binding<StageInteraction>?
        private var onDoubleTap: ((ViewPoint) -> Void)?
        private var onCommitted: (() -> Void)?

        /// Weak: the view owns the recognisers, which retain this as their target.
        private weak var trackingView: StageTouchTrackingView?

        /// Set by a cancel, cleared when the last finger leaves. See rule 3.
        private var isSuppressed = false

        override init() {
            super.init()
            // **One wiring line for three recognisers**, because a deleted `addTarget` is a
            // mutation no test in this repo can catch: UIKit exposes no way to read a
            // recogniser's targets back, and the suite drives the action methods directly. The
            // consequence of losing the *pan*'s target is this story's original defect exactly —
            // a two-finger pinch that zooms and does not translate (`/codex-review` round 1,
            // finding 2). Consolidating does not close the blind spot; it reduces it from three
            // independent lines to one, and the device session's checks 1–3 exercise all three.
            for (recognizer, action) in [
                (pinch as UIGestureRecognizer, #selector(pinched)),
                (pan as UIGestureRecognizer, #selector(panned)),
                (tap as UIGestureRecognizer, #selector(doubleTapped))
            ] {
                recognizer.addTarget(self, action: action)
            }

            pan.minimumNumberOfTouches = 1
            pan.maximumNumberOfTouches = 2
            tap.numberOfTapsRequired = 2

            for recognizer in [pinch, pan, tap] as [UIGestureRecognizer] {
                recognizer.delegate = self
                // **Both of these are load-bearing, not hygiene.**
                //
                // `cancelsTouchesInView`: at its default the tracking view stops receiving
                // `touchesEnded` the moment a recogniser recognises, so the touch count — the
                // terminal signal the commit depends on — would freeze above zero forever.
                //
                // `delaysTouchesEnded`: at its default the tap recogniser holds the view's
                // `touchesEnded` for the double-tap interval, so every commit, and the settled
                // re-bake behind it, would arrive ~0.3 s after the fingers left the glass —
                // landing squarely in the tail that device capture #2 exists to attribute, and
                // being misread as evidence for the commit hypothesis.
                recognizer.cancelsTouchesInView = false
                recognizer.delaysTouchesEnded = false
            }
        }

        func install(on view: StageTouchTrackingView) {
            trackingView = view
            view.addGestureRecognizer(pinch)
            view.addGestureRecognizer(pan)
            view.addGestureRecognizer(tap)
            view.onTouchCountChanged = { [weak self] count in self?.touchCountChanged(to: count) }
            view.onTouchesCancelled = { [weak self] in self?.cancel() }
        }

        func update(
            snapshot: Snapshot,
            manipulation: Binding<StageManipulation>,
            interaction: Binding<StageInteraction>,
            onDoubleTap: @escaping (ViewPoint) -> Void,
            onCommitted: (() -> Void)?
        ) {
            self.snapshot = snapshot
            self.manipulation = manipulation
            self.interaction = interaction
            self.onDoubleTap = onDoubleTap
            self.onCommitted = onCommitted
        }

        // MARK: - The pinch channel

        @objc func pinched(_ recognizer: UIPinchGestureRecognizer) {
            guard !isSuppressed else { return }
            switch recognizer.state {
            case .began:
                beginManipulating()
                // **Read after the interrupt, never before.** `beginManipulating` ends any fit
                // animation at its visible progress, which moves the baseline; a range computed
                // first would clamp against the animation's destination while the user pinches
                // against what is on screen (`/codex-review` round 2 on US-313a).
                let limits = interaction?.wrappedValue
                    .magnificationLimits(fitting: snapshot.fitted)
                    ?? StageManipulation.unlimitedMagnification
                // Reset at `.began` and **never** at `.changed`: the recogniser's scale is
                // cumulative from its own begin, which is what the tracker's contract expects.
                // Resetting per change would turn it into an incremental value and compound it.
                recognizer.scale = 1
                manipulation?.wrappedValue.pinchBegan(
                    scale: 1,
                    centroid: ViewPoint(recognizer.location(in: recognizer.view)),
                    within: limits
                )
            case .changed:
                manipulation?.wrappedValue.pinchChanged(to: Double(recognizer.scale))
            case .ended:
                manipulation?.wrappedValue.pinchEnded()
                settleIfFinished()
            case .cancelled, .failed:
                cancel()
            case .possible:
                // `.recognized` is `.ended` under another name and is matched above; `.failed`
                // dispatches no action message at all, so the arm above it is really the
                // cancelled one and is kept for the compiler's exhaustiveness rather than for a
                // path UIKit takes (`swift-code-reviewer`, S7).
                break
            @unknown default:
                break
            }
        }

        // MARK: - The pan channel

        @objc func panned(_ recognizer: UIPanGestureRecognizer) {
            guard !isSuppressed else { return }
            switch recognizer.state {
            case .began:
                beginManipulating()
                // **Taken as reported, threshold included — never re-based to zero.** US-307
                // measured the subtraction and removed it: a 101 pt drag whose live frame
                // showed 91 committed 101, so the content jumped forward at finger-lift. With a
                // pinch live it is worse than cosmetic, because the grabbed points stop
                // tracking the fingers. `setTranslation(.zero, in:)` here is the single most
                // likely wrong reflex in this file.
                manipulation?.wrappedValue.panBegan(
                    at: ViewPoint(recognizer.translation(in: recognizer.view))
                )
            case .changed:
                manipulation?.wrappedValue.panChanged(
                    to: ViewPoint(recognizer.translation(in: recognizer.view))
                )
            case .ended:
                manipulation?.wrappedValue.panEnded()
                settleIfFinished()
            case .cancelled, .failed:
                cancel()
            case .possible:
                // `.recognized` is `.ended` under another name and is matched above; `.failed`
                // dispatches no action message at all, so the arm above it is really the
                // cancelled one and is kept for the compiler's exhaustiveness rather than for a
                // path UIKit takes (`swift-code-reviewer`, S7).
                break
            @unknown default:
                break
            }
        }

        // MARK: - The double tap

        @objc func doubleTapped(_ recognizer: UITapGestureRecognizer) {
            guard !isSuppressed else { return }
            onDoubleTap?(ViewPoint(recognizer.location(in: recognizer.view)))
        }

        // MARK: - Terminating

        /// A touch sequence that has reached zero fingers is a terminal signal in its own
        /// right, and **not only when a recogniser says so**.
        ///
        /// Two fingers can land, pinch without passing the pan's slop, and lift one by one: the
        /// pinch ends while touches remain (correctly, no commit), and then the last finger
        /// leaves with no recogniser left to send an action. Without this the manipulation
        /// would stay live for the rest of the session.
        func touchCountChanged(to count: Int) {
            guard count == 0 else { return }
            isSuppressed = false
            settleIfFinished()
        }

        private func beginManipulating() {
            // Idempotent and inert when nothing is animating, so every channel's `.began` may
            // call it without tracking which was first. It is what makes the baseline something
            // that cannot move under the fingers — the assumption the tracker's rebase makes.
            guard let manipulation else { return }
            interaction?.wrappedValue.beginManipulating(
                joining: manipulation.wrappedValue,
                fitting: snapshot.fitted,
                settlingAt: snapshot.settlingProgress
            )
        }

        private func settleIfFinished() {
            guard let manipulation, let interaction else { return }
            let touchesRemain = (trackingView?.activeTouchCount ?? 0) > 0
            guard let gesture = manipulation.wrappedValue.finish(
                in: snapshot.viewport, touchesRemain: touchesRemain
            ) else { return }

            interaction.wrappedValue.commit(
                gesture,
                fitting: snapshot.fitted,
                in: snapshot.viewport,
                settlingAt: snapshot.settlingProgress
            )
            onCommitted?()
        }

        private func cancel() {
            manipulation?.wrappedValue.cancelled()
            isSuppressed = true
        }

        // MARK: - The delegate

        /// **Scoped to our own pair.** A blanket `true` would also tell `NavigationStack`'s
        /// interactive-pop recogniser it may run simultaneously with the pan, which would turn
        /// "the one-finger pan keeps the existing conflict, and that is the shipped state"
        /// into a regression this story authorised.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            owns(gestureRecognizer) && owns(other)
        }

        /// No failure requirement in either direction, which is what keeps the pan from being
        /// delayed by the double-tap interval. UIKit exposes no getter for a recogniser's
        /// failure requirements, so this delegate answer is the only part a test can read back;
        /// that the two really do coexist in the hand is human check 3.
        func gestureRecognizer(
            _: UIGestureRecognizer,
            shouldRequireFailureOf _: UIGestureRecognizer
        ) -> Bool {
            false
        }

        func gestureRecognizer(
            _: UIGestureRecognizer,
            shouldBeRequiredToFailBy _: UIGestureRecognizer
        ) -> Bool {
            false
        }

        private func owns(_ recognizer: UIGestureRecognizer) -> Bool {
            recognizer === pinch || recognizer === pan || recognizer === tap
        }
    }
}
