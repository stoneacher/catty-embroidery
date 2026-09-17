import StagePreview
import SwiftUI
import UIKit

/// The stage's input layer: a `UIPinchGestureRecognizer` and a `UIPanGestureRecognizer` that
/// recognise together, plus the double tap, feeding US-313a's pure `StageManipulation`.
///
/// **Why UIKit at all, when the stage was built on SwiftUI gestures.** `DragGesture` is a
/// single-touch recogniser: with two fingers down its translation is not the centroid's, so
/// lateral movement during a pinch is largely dropped — which is exactly what Sebastian
/// reported from the device session. `UIPanGestureRecognizer.translation(in:)` *is* the
/// centroid's, and it stays continuous when a finger is added or removed. That one property is
/// the whole reason for the pair, and it is why a hand-rolled `UIGestureRecognizer` subclass
/// would be harder rather than simpler: rolling your own means re-implementing the centroid
/// re-basing, and getting it wrong is what visibly jumps.
///
/// `UIGestureRecognizerRepresentable` would be the modern spelling and is iOS 18, against this
/// app's iOS 17 floor (ADR-004). `UIScrollView` was rejected on evidence in US-313a's planning.
///
/// **No arithmetic happens in this file.** Every action method reads the recogniser's plain
/// numbers and calls the package. That is what makes the interesting half testable, and it is
/// ADR-028's own rewrite lesson applied one level further out: the area with the worst defect
/// history in this repo had zero automated cover, and six review rounds found the same
/// conceptual mistake in four spellings.
struct StageManipulationCatcher: UIViewRepresentable {
    /// Everything the coordinator needs from the view, as one value.
    ///
    /// **Named `Snapshot` rather than `Context`** because `UIViewRepresentable` already has a
    /// `Context`, and shadowing it inside the conforming type is a confusion no comment fixes.
    struct Snapshot {
        let fitted: StageTransform
        let viewport: ViewSize
        /// The fit animation's **visible** progress, straight from the `SettlingProgress` shim.
        ///
        /// Load-bearing, and ADR-028's Codex round 8 is why: the model's stored progress jumps
        /// to 1 the instant `withAnimation` runs, and only the shim's closure holds the
        /// interpolated value. A catcher built outside the shim would interrupt an animation at
        /// its *destination*, snapping the stage from what the user can see to where it was
        /// heading.
        let settlingProgress: Double

        /// What a coordinator holds before its first update — a degenerate viewport, which
        /// every package method is total for.
        static let placeholder = Snapshot(
            fitted: StageTransform.fitting(StageGeometry.box, in: .zero),
            viewport: .zero,
            settlingProgress: 1
        )
    }

    let snapshot: Snapshot

    /// View-local, like the `@GestureState` it replaces: touch delivery is per-view, and a
    /// size-class change that destroys the view also cancels the recognisers.
    @Binding var manipulation: StageManipulation

    /// `AppModel`'s, because `RootView` builds the stage at two call sites (ADR-023).
    @Binding var interaction: StageInteraction

    /// The one thing the coordinator cannot do itself: `withAnimation` with the view's
    /// `accessibilityReduceMotion`, and the completion that ends the animation it started.
    let onDoubleTap: (ViewPoint) -> Void

    /// Called after a manipulation commits. **The debug commit counter's only call site**, and
    /// it is supplied by the view rather than recorded here so that process-wide mutable state
    /// stays out of the parallel test suites that drive this coordinator.
    let onCommitted: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> StageTouchTrackingView {
        let view = StageTouchTrackingView()
        context.coordinator.install(on: view)
        apply(to: context.coordinator)
        return view
    }

    /// **Four assignments, and nothing else may ever happen here.**
    ///
    /// This runs on every evaluation of the `SettlingProgress` shim's body — every animation
    /// frame, every run batch, every touch move. Re-creating or re-installing a recogniser from
    /// here would cancel the gesture in flight, which is the single most dangerous thing this
    /// method could do and is invisible in a screenshot;
    /// `updatingDoesNotReinstallTheRecognizers` is the guard.
    func updateUIView(_: StageTouchTrackingView, context: Context) {
        apply(to: context.coordinator)
    }

    private func apply(to coordinator: Coordinator) {
        coordinator.update(
            snapshot: snapshot,
            manipulation: $manipulation,
            interaction: $interaction,
            onDoubleTap: onDoubleTap,
            onCommitted: onCommitted
        )
    }
}
