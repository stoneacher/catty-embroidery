import StagePreview
import SwiftUI

/// The drawn stage: the hoop, the design, the needle — and the gestures that inspect them.
///
/// **Split out of `StageView` because that file had 43 lines left before SwiftLint's hard
/// 400** (CI runs `--strict`, so the default `file_length` warning is an error). This was the
/// coherent seam: everything here is about *looking at* the design, where what remains in
/// `StageView` is about the design's state and what to say when there is none.
///
/// **No arithmetic in this file reaches a `StageTransform`**, which is US-307's first
/// criterion, stated at the width it actually holds. Every number that goes *into* a
/// transform is produced by a pure method in `StagePreview` — the fit, the anchored pinch,
/// the pan, the adjustable step, the animation delta — and the two conversions on the way in
/// (`CGSize` → `ViewPoint`, `UnitPoint`'s two `Double`s → `ViewPoint`) are bridges rather
/// than math, living outside this file so ADR-022's isolation test can see them.
///
/// The broader claim — "no transform arithmetic here at all" — was made first and was not
/// true: the effect channel below composes `.scaleEffect`/`.offset` by hand, and an earlier
/// version also subtracted the drag's threshold before handing the pan over, which is
/// exactly the arithmetic that turned out to be wrong (see `LiveGesture.pan`). The effect
/// composition stays, because it is view-space presentation that never reaches a transform;
/// the subtraction is gone.
struct StageCanvas<Renderer: StagePreviewRenderer>: View {
    let display: StitchDisplayList
    let runState: RunState
    let needle: PreviewNeedle?
    let renderer: Renderer

    /// The summary the accessibility value reads. Comes from the run's phase, so it is
    /// rebuilt on run-state transitions only — never per batch, which is this story's
    /// headline requirement and is enforced in the package rather than here.
    let summary: StageSummary

    /// The design's name, for the accessibility label. `nil` before anything is picked.
    let designName: String?

    @Binding var zoom: StageZoom

    /// The gesture in flight, **absolute since it began** — never accumulated.
    ///
    /// `MagnifyGesture.Value.magnification` and `DragGesture.Value.translation` are both
    /// cumulative from the gesture's start, so folding each callback in as a delta would
    /// compound them: a pinch whose callbacks read 2, 2, 2 would land at 8× for fingers that
    /// only ever asked for 2×. Holding the absolute value and committing once is what avoids
    /// that; `StageZoomTests.committingTwiceCompounds` pins the package half (commit is not
    /// idempotent, so the caller must call it once), and the view half is verified on the
    /// simulator, since no unit test can observe how many times a gesture calls it.
    ///
    /// `@GestureState` rather than `@State`, because it resets itself when a gesture ends —
    /// including one the system cancels for an incoming call, a backgrounding, or VoiceOver
    /// taking over. A cancelled gesture cannot leave the canvas stuck scaled.
    @GestureState private var live = LiveGesture()

    /// The fit animation in flight, or `nil`.
    ///
    /// Holds the two endpoints and a progress the animation drives, rather than a rendered
    /// layer's scale and offset. That is the difference between animating *what is drawn* and
    /// animating *the drawing*: only the first can bring content that was off-screen back
    /// into frame, which a zoom-out to fit does by definition.
    @State private var settling: SettlingFit?

    /// Which fit animation a completion handler belongs to.
    ///
    /// **Not defensive.** `withAnimation(_:completionCriteria:_:completion:)` fires its
    /// completion unconditionally, and `.gesture` stays live for the whole 0.35 s spring — so
    /// a flick-pan finishing inside that window committed into `zoom` and was then silently
    /// overwritten by `fitToContent()`. Measured by `swift-code-reviewer` with the spring
    /// widened to 6 s: a pan committed mid-animation left the hoop at exactly the fitted
    /// edge, i.e. the commit was gone. A flick-pan is comfortably under 350 ms, so the
    /// window is narrow and reachable rather than theoretical.
    @State private var settleGeneration = 0

    /// The single gate ADR-027 asks this story to reuse rather than add a second of. The
    /// *policy* lives in `StageMotion`; this is just the environment read, which is per-view
    /// by design — passing the flag down as a parameter would decouple it from the
    /// environment SwiftUI actually resolves for this view.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let viewport = ViewSize(proxy.size)
            let fitted = StageTransform.fitting(
                StageGeometry.fitTarget(including: display.bounds), in: viewport
            )
            let committed = zoom.resolved(fitting: fitted)

            StageInterpolatedCanvas(
                progress: settling?.progress ?? 0,
                from: settling?.from ?? committed,
                to: settling?.to ?? committed
            ) { animated in
                let current = liveTransform(committed: animated, fitting: fitted, in: viewport)
                // **Liveness is whether an interaction is in flight, not whether the two
                // transforms happen to differ.** Comparing them looks equivalent and is not:
                // a gesture returned to its own baseline mid-pinch, or the first frame of a
                // fit animation, makes them equal while fingers are still down — and the
                // renderer would then treat the frame as settled and rasterise into the
                // middle of the gesture, which is the work the split exists to defer (Codex
                // round 2).
                let render: StageRenderTransform = isInteracting
                    ? .live(bake: committed, current: current)
                    : .settled(committed)

                ZStack {
                    StageFieldView(transform: current)
                    renderer.makeBody(
                        display: display, transform: render, needle: needle, viewport: viewport
                    )
                }
            }
            // **The mat, painted behind the canvas rather than inside it.**
            //
            // `StageFieldView` fills the canvas with the mat, but only across the canvas's own
            // bounds; a design panned far enough leaves the field's edge visible, and before
            // this the pane's grouped-background grey showed through (reported by Sebastian
            // from the running app). Behind everything, this can only ever be the colour the
            // stage's outside already is.
            .background(StageChrome.outsideField)
            // Grabbable across the whole slot rather than only where ink was stroked.
            .contentShape(Rectangle())
            .gesture(inspectGesture(viewport: viewport, fitted: fitted))
            // **A separate modifier, not part of the composition above.** The drag's default
            // 10 pt minimum distance is what lets these coexist — a double tap never moves,
            // so the drag never claims it. That makes the pan's threshold load-bearing for a
            // criterion that looks unrelated to it, and it is **measured, not assumed**:
            // building with `DragGesture(minimumDistance: 0)` — which would have removed the
            // threshold and with it the pan's start-jump — made the double-tap a byte-for-byte
            // no-op on the simulator.
            .onTapGesture(count: 2) { resetToFit(from: committed, to: fitted, in: viewport) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(StageAccessibility.label(designName: designName))
            .accessibilityValue(
                StageAccessibility.value(
                    summary: summary,
                    state: runState,
                    magnification: zoom.magnification(fitting: fitted)
                )
            )
            .accessibilityHint(StageAccessibility.hint(for: runState))
            .accessibilityAddTraits(.isImage)
            // Criterion 7: zoom without gestures, for VoiceOver and Switch Control.
            .accessibilityAdjustableAction { direction in
                adjust(direction, fitting: fitted, in: viewport)
            }
            // **Required rather than a nicety.** Double-tap-to-fit is unreachable with
            // VoiceOver running — a double tap is VoiceOver's own activate gesture — and
            // Switch Control has no double tap at all. Without this, a user who zooms in has
            // no way back, which would make criterion 7 deliver a trap instead of a feature.
            .accessibilityAction(named: Text(.stageCanvasAccessibilityActionFit)) {
                resetToFit(from: committed, to: fitted, in: viewport)
            }
        }
    }

    /// Whether a gesture or the fit animation is in flight.
    private var isInteracting: Bool {
        live.isActive || settling != nil
    }

    /// The transform this frame draws with: the committed one, moved by whatever gesture is
    /// in flight.
    ///
    /// **Computed through `StageZoom.previewing`, which is the same function `commit` calls.**
    /// The frame the user sees and the transform they get on release are therefore one
    /// computation rather than two that must agree — a property this story had already got
    /// wrong in the opposite direction once.
    private func liveTransform(
        committed: StageTransform,
        fitting fitted: StageTransform,
        in viewport: ViewSize
    ) -> StageTransform {
        guard live.isActive else { return committed }

        // **The baseline is passed, never faked.** An earlier version copied `zoom` and called
        // `overriding(committed)` so the animation's interpolated transform could act as the
        // starting point — which set `settled`, so the copy was no longer "following the fit"
        // and the identity guard inside `previewing` could not fire. The frame then re-derived
        // a transform one ULP from the fit while `commit`, using the real `zoom`, kept the fit
        // exactly: preview and commit disagreed at release, which is the regression round 5
        // had just removed, reappearing one layer up (Codex round 6).
        return zoom.previewing(
            magnification: Double(live.magnification),
            anchor: ViewPoint(unitX: live.anchor.x, unitY: live.anchor.y, in: viewport),
            pan: ViewPoint(live.pan),
            fitting: fitted,
            from: committed
        )
    }

    // MARK: - Gestures

    /// Pinch and pan **simultaneously**, folded in once when the gesture ends.
    ///
    /// One `onEnded` for the pair rather than one per channel: both values are absolute since
    /// the start, so committing them together is the whole gesture applied exactly once, in a
    /// pinned order (`StageZoom.commit` applies the pinch before the pan, because the anchor
    /// is a start-frame coordinate).
    private func inspectGesture(viewport: ViewSize, fitted: StageTransform) -> some Gesture {
        MagnifyGesture()
            .simultaneously(with: DragGesture())
            .updating($live) { value, state, _ in
                state.isActive = true
                if let pinch = value.first {
                    state.magnification = pinch.magnification
                    state.anchor = pinch.startAnchor
                }
                if let pan = value.second {
                    state.pan = pan.translation
                }
            }
            .onChanged { _ in
                // **A gesture ends the fit animation at its destination, at the moment the
                // gesture starts.** Without this the two disagree: the frame is drawn from the
                // interpolated transform while `commit` reads `zoom`, which still holds the
                // *pre-animation* value — so interrupting a reset from 4× and releasing jumped
                // from "halfway to fit, plus your drag" to "4×, plus your drag" (Codex round
                // 3). Finishing the fit first means the gesture starts from what the animation
                // was heading for, so the only movement the user did not ask for happens at
                // the instant they touched the screen, which is the honest place for it.
                settleImmediately()
            }
            .onEnded { value in

                zoom.commit(
                    // `CGFloat` → `Double` explicitly: the package takes `Double` so that no
                    // CoreGraphics type crosses ADR-022's boundary, and an implicit widening
                    // is exactly the shortcut the isolation test exists to make impossible.
                    magnification: Double(value.first?.magnification ?? 1),
                    anchor: anchorPoint(of: value.first, in: viewport),
                    pan: ViewPoint(value.second?.translation ?? .zero),
                    fitting: fitted
                )
            }
    }

    /// The pinch's centre as a view point, or the viewport's centre when there was no pinch.
    ///
    /// Derived from `startAnchor` rather than `startLocation` so the point the *effect* is
    /// anchored on and the point the *commit* is anchored on have one source. Two spellings
    /// of the same anchor is where a pinch drifts by a few points on release.
    private func anchorPoint(of pinch: MagnifyGesture.Value?, in viewport: ViewSize) -> ViewPoint {
        guard let pinch else { return viewport.center }
        return ViewPoint(unitX: pinch.anchorUnitX, unitY: pinch.anchorUnitY, in: viewport)
    }

    // MARK: - Programmatic transform changes

    /// Double-tap, and the "Fit to Hoop" accessibility action.
    ///
    /// **Animates a `Double` and re-strokes the canvas at each step**, rather than sliding the
    /// already-rendered canvas with `.scaleEffect`/`.offset`. The first version did the
    /// latter, and it could not work: a reset from a zoomed-in view is a zoom *out*, which by
    /// definition brings content into frame that the canvas never drew, so the animation
    /// played over a layer with blank edges until it finished. Re-stroking costs a frame's
    /// worth of `Path` building per step — at M3's counts, nothing; at 50 000, US-309's to
    /// measure, and it is the same mid-gesture path that story is already told to measure.
    ///
    /// The bake key stays on the committed transform throughout, so the settled raster is
    /// **not** rebuilt during the animation; it is rebuilt once, when the transform swaps at
    /// completion.
    ///
    /// Reduce Motion passes `nil`, which is a legal animation meaning "instantly", so one call
    /// site serves both branches with no branch of its own.
    private func resetToFit(from current: StageTransform, to fitted: StageTransform, in viewport: ViewSize) {
        // A second double-tap while the first is still animating would otherwise start from
        // `zoom` — which still holds the *pre-animation* transform — and snap backwards past
        // what is on screen before animating forward again (Codex round 4). Finishing the
        // animation first makes the repeat a no-op, because the stage is then already fitted.
        settleImmediately()

        guard !zoom.isFollowingFit else { return }

        settleGeneration &+= 1
        let generation = settleGeneration
        settling = SettlingFit(from: current, to: fitted, progress: 0)

        withAnimation(StageMotion.fitAnimation(reduceMotion: reduceMotion)) {
            settling?.progress = 1
        } completion: {
            // A gesture that committed while this spring was running has already bumped the
            // generation; finishing the fit here would throw that commit away.
            guard settleGeneration == generation else { return }
            zoom.fitToContent()
            settling = nil
        }
    }

    /// Ends a fit animation immediately, at the destination it was heading for.
    ///
    /// Bumping the generation is what stops the in-flight completion handler running later and
    /// undoing whatever replaced it.
    private func settleImmediately() {
        guard settling != nil else { return }

        settleGeneration &+= 1
        zoom.fitToContent()
        settling = nil
    }

    /// One activation of the adjustable action.
    ///
    /// **Deliberately not animated.** Criterion 8 names the double-tap transition and only
    /// that; an assistive user stepping the zoom gains nothing from a spring, and the value
    /// VoiceOver speaks afterwards should describe where the stage *is*, not where it is
    /// heading.
    private func adjust(
        _ direction: AccessibilityAdjustmentDirection,
        fitting fitted: StageTransform,
        in viewport: ViewSize
    ) {
        // For the reason the gesture does it: otherwise the pending completion calls
        // `fitToContent()` 0.35 s later and silently discards the adjustment, and the animation
        // keeps rendering the old value in the meantime (Codex round 3). Reachable through the
        // "Fit to Hoop" action followed immediately by an increment, which is an ordinary thing
        // for a VoiceOver user to do.
        settleImmediately()

        switch direction {
        case .increment: zoom.adjust(.zoomIn, fitting: fitted, in: viewport)
        case .decrement: zoom.adjust(.zoomOut, fitting: fitted, in: viewport)
        @unknown default: break
        }
    }

}
