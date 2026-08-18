/// Which way an `.accessibilityAdjustableAction` was swiped.
///
/// A named pair rather than SwiftUI's `AccessibilityAdjustmentDirection`, because
/// `StagePreview` is Foundation-only (ADR-022) and because "increment" says nothing about
/// which way a *zoom* goes. The app maps one onto the other in one line.
public enum StageZoomAdjustment: Hashable, Sendable {
    case zoomIn
    case zoomOut
}

/// The user's own zoom and pan, or its absence.
///
/// **`nil` means "follow the fit", and that is the load-bearing design decision.** A stored
/// snapshot of the fitted transform would freeze at whatever the viewport was when the
/// snapshot was taken, so a rotation, an iPad resize or a design growing outside the hoop
/// mid-run would all leave the stage fitted to a viewport that no longer exists. With the
/// absence of a value meaning "fit", every one of those keeps refitting for free, and
/// double-tap-to-fit is one assignment rather than a recomputation the view could get wrong.
///
/// **Nothing here is written during a gesture.** `MagnifyGesture.Value.magnification` and
/// `DragGesture.Value.translation` are both cumulative from the gesture's start, so the
/// committed transform *is* the gesture's baseline for its whole duration and `commit` needs
/// no captured baseline, no rebasing and no per-channel end bookkeeping. The live gesture is
/// a `.scaleEffect`/`.offset` over the rendered canvas (see `ViewDelta`), which is also what
/// keeps the settled raster's bake key from churning 60 times a second.
///
/// Owned by `AppModel` rather than held as `@State` in the stage, for two reasons and the
/// second is the worse one: ADR-023 records that `RootView` swaps one navigation container
/// for another on a horizontal size-class change and tears down whatever the abandoned
/// container owned, and `RootView` builds the stage at **two** call sites — so `@State`
/// there would be two independent zooms that disagree.
public struct StageZoom: Equatable, Sendable {
    /// One activation of the adjustable action, as a **multiplicative** factor.
    ///
    /// Multiplicative because the range spans three orders of magnitude (0.05 … 50): an
    /// additive step usable at 0.05 is imperceptible at 50, and vice versa. 1.5 reaches the
    /// maximum from a typical in-hoop fit (about 0.6) in roughly eleven activations and the
    /// floor in six — enough resolution to frame a region, few enough presses that a Switch
    /// Control user is not on a treadmill. 1.25 needs four activations to double; 2.0
    /// overshoots in two the ~3× ceiling ADR-027 records for the needle's legibility.
    public static let adjustmentStep: Double = 1.5

    /// The user's explicit transform, or `nil` while the stage follows the fit.
    public private(set) var settled: StageTransform?

    public init() {}

    public var isFollowingFit: Bool {
        settled == nil
    }

    /// The transform to render with, given the fit for the current viewport and content.
    public func resolved(fitting fit: StageTransform) -> StageTransform {
        settled ?? fit
    }

    /// How far the user has zoomed **relative to the fit** — 1.0 means "fitted".
    ///
    /// Relative, because this is what gets spoken. View points per stage point is a number
    /// with no meaning to anyone; "300 per cent" is one a user can act on. `fit.scale` is
    /// guaranteed positive and finite by the `StageTransform` chokepoint, so this cannot
    /// divide by zero.
    public func magnification(fitting fit: StageTransform) -> Double {
        // Red-phase stub.
        _ = fit
        return 0
    }

    /// Folds a finished gesture in: pinch about `anchor`, then pan by `pan`.
    ///
    /// **The order is pinned and it matters.** `anchor` is a view point measured in the
    /// gesture's *start* frame, so it only identifies the stage point the user grabbed while
    /// the pan has not yet been applied. Panning first would anchor the zoom about whatever
    /// happened to be under that coordinate afterwards — a visible jump on any gesture that
    /// both pinched and dragged, which is most of them.
    ///
    /// Clamped through `StageZoomBounds(fitting:)`, so an out-of-hoop design can be pinched
    /// back out to its own fit instead of snapping larger.
    public mutating func commit(
        magnification: Double,
        anchor: ViewPoint,
        pan: ViewPoint,
        fitting fit: StageTransform
    ) {
        // Red-phase stub.
        _ = (magnification, anchor, pan, fit)
    }

    /// Back to following the fit — the double-tap, and the "Fit to Hoop" accessibility
    /// action that is the only route back for a VoiceOver or Switch Control user.
    public mutating func fitToContent() {
        // Red-phase stub.
    }

    /// One activation of the adjustable action.
    ///
    /// Anchored on the **viewport's centre**: there is no finger to anchor on, and the
    /// centre is where the fit put the design's centre, so repeated activations zoom into
    /// the middle of the hoop rather than drifting. Anchoring on the stage origin instead
    /// would walk a panned design off-screen.
    ///
    /// Uses the same bounds as a gesture rather than a narrower assistive range. A narrower
    /// range was considered — floored at the fit, so zoom-out could not reveal only mat —
    /// and rejected because the zoom level is now spoken: a user who reaches 50 per cent is
    /// *told* so, which is what the narrower range was invented to compensate for, and the
    /// "Fit to Hoop" action returns in one step regardless. One bounds concept, not two.
    public mutating func adjust(
        _ direction: StageZoomAdjustment,
        fitting fit: StageTransform,
        in viewport: ViewSize
    ) {
        // Red-phase stub.
        _ = (direction, fit, viewport)
    }
}
