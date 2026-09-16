import UIKit

/// The view the three recognisers are attached to, which exists to answer one question the
/// recognisers cannot: **are there still fingers on the glass?**
///
/// **Why a recogniser cannot answer it.** `StageManipulation.finish(in:touchesRemain:)` commits
/// only when the last channel ends *and* the touches are gone, because UIKit starts a pan only
/// after enough movement — so two fingers can land, pinch, and one lift with the pan still
/// `.possible`. US-313a got that far. What neither story's design noticed is that the same
/// sequence removes the *terminal signal* as well: when the last finger lifts, the pinch has
/// already ended and the pan never recognised, so **no action method runs at all**. Nothing asks
/// `finish` again. The manipulation stays live forever, `canUseRaster` stays false, and the
/// design stays coarse for the rest of the session — the catastrophe the cancellation rule was
/// written to prevent, reached through the commit rule instead.
///
/// So the touch count is a terminal signal in its own right, and reaching zero attempts the
/// settle exactly as a recogniser's `.ended` does. `finish` is idempotent, so attempting from
/// both costs nothing and makes the order UIKit happens to deliver them in irrelevant.
///
/// **The count is maintained as an integer with internal mutators, and that is a testability
/// decision stated rather than hidden**: `UITouch` has no public initialiser, so no test can
/// synthesise a touch sequence. Tests drive the count; that UIKit delivers these callbacks at
/// all is human checks 1–3, on a device. The count is clamped at zero so a doubled or
/// unbalanced delivery degrades to "no fingers" rather than to a stuck-live stage — the failure
/// this whole type exists to prevent.
final class StageTouchTrackingView: UIView {
    /// Told whenever the count changes, with the new count.
    var onTouchCountChanged: ((Int) -> Void)?

    /// Told when the system takes the touches away, which is **not** the same event as the
    /// count reaching zero and must never be treated as one: a clean end commits, a cancel
    /// does not.
    var onTouchesCancelled: (() -> Void)?

    private(set) var activeTouchCount = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        // Transparent and hit-testable: the recognisers need the touches, the stage needs the
        // pixels. `isUserInteractionEnabled` is already true by default for a plain `UIView`.
        backgroundColor = .clear
        // **The whole terminal signal depends on this line, and it defaults to `false`.**
        //
        // A `UIView` that is not multi-touch enabled receives only the *first* touch of a
        // sequence, while its gesture recognisers receive them all — so the pinch worked
        // perfectly and the count silently stayed at 1 with two fingers down. The consequence is
        // the exact invariant this type exists to protect, inverted: fingers A and B land
        // (count 1), A lifts, the view reports **zero**, and the pinch's `.ended` then commits
        // with B still on the glass. `StageInteraction.settled` is written mid-gesture, which
        // ADR-030 §7 forbids, and if B then crosses the pan's slop it starts a second
        // manipulation that commits again — two commits from one touch sequence.
        //
        // Found by `/codex-review` round 1. The in-loop review walked both delivery orders and
        // missed it because it took the count as given; the tests missed it because they call
        // `touchesArrived(2)` directly, which is the one thing UIKit would not have done.
        isMultipleTouchEnabled = true
        // **AC7, set here rather than in `makeUIView`**, which is what lets a test assert it on
        // a plain constructor instead of walking a published accessibility tree — the technique
        // US-307 had to delete after it passed locally and failed unreproducibly on CI.
        isAccessibilityElement = false
        accessibilityElementsHidden = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("StageTouchTrackingView is created in code, never from a nib")
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        touchesArrived(touches.count)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        touchesLeft(touches.count)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        touchesCancelledByTheSystem(count: touches.count)
    }

    func touchesArrived(_ count: Int) {
        activeTouchCount += count
        onTouchCountChanged?(activeTouchCount)
    }

    func touchesLeft(_ count: Int) {
        activeTouchCount = max(0, activeTouchCount - count)
        onTouchCountChanged?(activeTouchCount)
    }

    /// The system took the touches away — an incoming call, a competing recogniser, the view
    /// going away mid-gesture.
    ///
    /// **The cancellation and the count change are both reported, in that order, and the order
    /// is the fix for a defect this file shipped.** The first version decremented the count
    /// silently and then reported only the cancel, so on the ordinary path — the system taking
    /// *every* touch — the count reached zero with nothing observing it. The coordinator sets
    /// its suppression flag on a cancel and clears it only when the count reaches zero, so the
    /// flag stayed set and the **entire next touch sequence was swallowed**: no pinch, no pan,
    /// no double tap, until those fingers lifted. Reachable every day, not exotically — on
    /// compact width a one-finger pan from the leading edge hands its touches to
    /// `NavigationStack`'s interactive pop, which cancels them (`swift-code-reviewer`).
    ///
    /// Reported in this order because the coordinator must reset its tracker before the count
    /// tells it the glass is clear; the settle it then attempts is a no-op against a tracker
    /// that has just been cleared, which is the intended outcome — a cancel commits nothing.
    ///
    /// **This is also the seam the tests drive**, and it is the production path rather than a
    /// parallel one: `UITouch` has no public initialiser, so the override above can only hand
    /// this method a count. A test calling it exercises every line the system does.
    func touchesCancelledByTheSystem(count: Int) {
        activeTouchCount = max(0, activeTouchCount - count)
        onTouchesCancelled?()
        onTouchCountChanged?(activeTouchCount)
    }
}
