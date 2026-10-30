#if DEBUG
    import CoreGraphics
    import StagePreview
    import UIKit

    /// US-316's scripted gesture: drives the stage's **real** `Coordinator` through its own
    /// action methods, with recognisers whose state and readings come from a `GestureScript`
    /// (brief D4).
    ///
    /// **A coordinator-path surrogate, not a finger.** From `panned(_:)`/`pinched(_:)` down
    /// everything is what a finger gets: the suppression gate, `beginManipulating`, the
    /// manipulation channels, the binding writes that invalidate the stage, the live render and
    /// its coarse plan, and at the end `settleIfFinished` → one commit. What UIKit does above the
    /// action methods — touch delivery, the recognisers' own state machines, arbitration, the
    /// touch counting — is skipped, and the calibration (D7) is what says whether that matters.
    ///
    /// **The commit arrives by a different route.** With no real touch down, `activeTouchCount`
    /// is 0 throughout, so the last channel's `.ended` commits. A finger's recognisers usually
    /// end while the view still counts the touch, and the commit then fires from
    /// `touchCountChanged(to: 0)`. Same commit, same count, different caller — and outside the
    /// recorded window either way, since a capture stops recording before the gesture ends
    /// (and the app exits before that commit's re-bake renders).
    @MainActor
    final class GestureDriver {
        private let coordinator: StageManipulationCatcher.Coordinator
        private let script: GestureScript
        private let pan = ScriptedPan()
        private let pinch = ScriptedPinch()

        init(coordinator: StageManipulationCatcher.Coordinator, script: GestureScript, viewport: ViewSize) {
            self.coordinator = coordinator
            self.script = script
            // Pinch about the stage's centre, so a zoom shrinks the design where it already is.
            pinch.scriptedLocation = CGPoint(x: viewport.width / 2, y: viewport.height / 2)
        }

        private var pinches: Bool {
            script.kind == .mixed
        }

        /// Puts the gesture down at rest, as a recogniser reports it at `.began`.
        func begin() {
            if pinches {
                pinch.scriptedState = .began
                pinch.scriptedScale = 1
                coordinator.pinched(pinch)
            }
            pan.scriptedState = .began
            pan.scriptedTranslation = script.translation(at: 0)
            coordinator.panned(pan)
        }

        /// Moves the gesture to where the script is `seconds` after it began.
        func advance(to seconds: Double) {
            if pinches {
                pinch.scriptedState = .changed
                pinch.scriptedScale = script.scale(at: seconds)
                coordinator.pinched(pinch)
            }
            pan.scriptedState = .changed
            pan.scriptedTranslation = script.translation(at: seconds)
            coordinator.panned(pan)
        }

        /// Lifts the gesture: each channel ends, and the last end commits.
        func end() {
            pan.scriptedState = .ended
            coordinator.panned(pan)
            if pinches {
                pinch.scriptedState = .ended
                coordinator.pinched(pinch)
            }
        }

        /// Condition C's pre-step: one pinch to `fraction` of the current scale, released.
        func zoom(to fraction: Double) {
            pinch.scriptedState = .began
            pinch.scriptedScale = 1
            coordinator.pinched(pinch)
            pinch.scriptedState = .changed
            pinch.scriptedScale = CGFloat(fraction)
            coordinator.pinched(pinch)
            pinch.scriptedState = .ended
            coordinator.pinched(pinch)
        }
    }

    /// A pan recogniser whose state and translation are set by the driver.
    ///
    /// Overrides rather than assignments, because UIKit swallows an assignment to `state` on a
    /// recogniser that is not in a view receiving touches — the pattern `StageManipulationDoubles`
    /// found to work.
    final class ScriptedPan: UIPanGestureRecognizer {
        var scriptedState: UIGestureRecognizer.State = .possible
        var scriptedTranslation: CGPoint = .zero

        override var state: UIGestureRecognizer.State {
            get { scriptedState }
            set { scriptedState = newValue }
        }

        override func translation(in _: UIView?) -> CGPoint {
            scriptedTranslation
        }
    }

    /// A pinch recogniser whose state, scale and centroid are set by the driver. The
    /// coordinator's `recognizer.scale = 1` at `.began` lands in `scriptedScale` and is harmless.
    final class ScriptedPinch: UIPinchGestureRecognizer {
        var scriptedState: UIGestureRecognizer.State = .possible
        var scriptedScale: CGFloat = 1
        var scriptedLocation: CGPoint = .zero

        override var state: UIGestureRecognizer.State {
            get { scriptedState }
            set { scriptedState = newValue }
        }

        override var scale: CGFloat {
            get { scriptedScale }
            set { scriptedScale = newValue }
        }

        override func location(in _: UIView?) -> CGPoint {
            scriptedLocation
        }
    }
#endif
