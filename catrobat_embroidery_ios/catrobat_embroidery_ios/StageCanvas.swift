import StagePreview
import SwiftUI

/// The drawn stage: the hoop, the design, the needle — and the gestures that inspect them.
///
/// **Split out of `StageView` because that file had 43 lines left before SwiftLint's hard
/// 400** (CI runs `--strict`, so the default `file_length` warning is an error). This was the
/// coherent seam: everything here is about *looking at* the design, where what remains in
/// `StageView` is about the design's state and what to say when there is none.
///
/// **There is no transform arithmetic in this file**, which is US-307's first criterion.
/// Every number that goes into a `StageTransform` is produced by a pure method in
/// `StagePreview` — the fit, the anchored pinch, the pan, the adjustable step, the animation
/// delta — and what is left here is composing gestures and handing their values over. The
/// two conversions that do happen (`CGSize` → `ViewPoint`, `UnitPoint`'s two `Double`s →
/// `ViewPoint`) are bridges rather than math, and both live outside this file so ADR-022's
/// isolation test can see them.
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
    /// that, and `StageZoomTests.onlyTheFinalCumulativeValueIsApplied` is what pins it.
    ///
    /// `@GestureState` rather than `@State`, because it resets itself when a gesture ends —
    /// including one the system cancels for an incoming call, a backgrounding, or VoiceOver
    /// taking over. A cancelled gesture cannot leave the canvas stuck scaled.
    @GestureState private var live = LiveGesture()

    /// The double-tap reset, mid-flight. `@State`, not `@GestureState`: it is app-initiated
    /// motion with a completion, not a gesture.
    @State private var settling = ViewDelta.identity

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
            let transform = zoom.resolved(fitting: fitted)

            ZStack {
                StageFieldView(transform: transform)
                renderer.makeBody(
                    display: display, transform: transform, needle: needle, viewport: viewport
                )
            }
            // **Criterion 3, and it is satisfied by what is *absent* here.** These two
            // modifiers scale the already-rendered canvas on the GPU; the `StageTransform`
            // they sit over is untouched until the gesture ends. So
            // `CanvasStitchLayers.BakeKey` — which reads the transform — cannot change
            // mid-gesture, and the settled raster is re-baked exactly once, on commit,
            // rather than sixty times a second. "Re-rasterised on gesture end" is therefore
            // true by construction rather than by timing.
            //
            // The accepted, stated trade-off: for the duration of a pinch-in the whole
            // canvas is magnified pixels, so it is soft until the fingers lift. Everything
            // fixed in view points — the needle, the hoop outline, the travel dash — grows
            // with the blit and snaps back at commit. That is a direct consequence of
            // ADR-027 fixing the needle in view points, and the alternative (scaling only
            // the stitch layer) is worse: the needle would visibly detach from the stitch it
            // is sewing.
            .scaleEffect(scaleEffect(for: live), anchor: live.anchor)
            .offset(offset(for: live))
            // Grabbable across the whole slot rather than only where ink was stroked.
            .contentShape(Rectangle())
            .gesture(inspectGesture(viewport: viewport, fitted: fitted))
            // **A separate modifier, not part of the composition above.** The drag's default
            // 10 pt minimum distance is what lets these coexist — a double tap never moves,
            // so the drag never claims it. That makes the pan's threshold load-bearing for a
            // criterion that looks unrelated to it.
            .onTapGesture(count: 2) { resetToFit(from: transform, to: fitted, in: viewport) }
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
                resetToFit(from: transform, to: fitted, in: viewport)
            }
        }
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
                if let pinch = value.first {
                    state.magnification = pinch.magnification
                    state.anchor = pinch.startAnchor
                }
                if let pan = value.second {
                    // The drag's threshold distance arrives in the first translation, so
                    // applying it raw would jump the content by 10 pt at pan start. The
                    // origin is subtracted out instead; the price, stated, is that the
                    // finger leads the content by that much for the rest of the pan.
                    if state.panOrigin == nil {
                        state.panOrigin = pan.translation
                    }
                    state.pan = pan.translation
                }
            }
            .onEnded { value in
                zoom.commit(
                    // `CGFloat` → `Double` explicitly: the package takes `Double` so that no
                    // CoreGraphics type crosses ADR-022's boundary, and an implicit widening
                    // is exactly the shortcut the isolation test exists to make impossible.
                    magnification: Double(value.first?.magnification ?? 1),
                    anchor: anchorPoint(of: value.first, in: viewport),
                    pan: ViewPoint(liveOffset(of: value.second)),
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

    private func liveOffset(of drag: DragGesture.Value?) -> CGSize {
        guard let drag else { return .zero }
        let origin = live.panOrigin ?? .zero
        return CGSize(
            width: drag.translation.width - origin.width,
            height: drag.translation.height - origin.height
        )
    }

    // MARK: - Programmatic transform changes

    /// Double-tap, and the "Fit to Hoop" accessibility action.
    ///
    /// Animated on the same `.scaleEffect`/`.offset` channel the gesture uses, because a
    /// `StageTransform` in state is not animatable — `Canvas` simply re-strokes from whatever
    /// it is handed, so `withAnimation` around the assignment animates nothing. The delta is
    /// pure package math; this only runs it and swaps the transform at completion.
    ///
    /// Reduce Motion passes `nil`, which is a legal animation meaning "instantly", so one
    /// call site serves both branches with no branch of its own.
    private func resetToFit(from current: StageTransform, to fitted: StageTransform, in viewport: ViewSize) {
        guard !zoom.isFollowingFit else { return }
        guard let delta = current.viewDelta(to: fitted, in: viewport) else {
            // Unrepresentable delta: swap without animating, which is always correct.
            zoom.fitToContent()
            return
        }

        withAnimation(StageMotion.fitAnimation(reduceMotion: reduceMotion)) {
            settling = delta
        } completion: {
            zoom.fitToContent()
            settling = .identity
        }
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
        switch direction {
        case .increment: zoom.adjust(.zoomIn, fitting: fitted, in: viewport)
        case .decrement: zoom.adjust(.zoomOut, fitting: fitted, in: viewport)
        @unknown default: break
        }
    }

    // MARK: - The live effect channel

    /// The gesture's magnification and the reset animation's, multiplied — they are never
    /// both in flight, so this is a union rather than a composition.
    private func scaleEffect(for live: LiveGesture) -> CGFloat {
        live.magnification * settling.scale
    }

    private func offset(for live: LiveGesture) -> CGSize {
        let origin = live.panOrigin ?? .zero
        return CGSize(
            width: live.pan.width - origin.width + settling.translation.x,
            height: live.pan.height - origin.height + settling.translation.y
        )
    }
}

/// A gesture's absolute state since it began. See `StageCanvas.live`.
struct LiveGesture: Equatable {
    var magnification: CGFloat = 1
    var anchor: UnitPoint = .center

    /// `nil` until the drag's first callback, which already carries the recognizer's
    /// threshold distance.
    var panOrigin: CGSize?
    var pan: CGSize = .zero
}

extension MagnifyGesture.Value {
    /// The pinch anchor's two components, so the package never sees a `UnitPoint`.
    var anchorUnitX: Double {
        startAnchor.x
    }

    var anchorUnitY: Double {
        startAnchor.y
    }
}

/// The hoop and the two fields, drawn beneath whatever the renderer produces.
///
/// **The hoop is an outline and is not clipped to.** Nothing here masks the renderer, so a
/// design that leaves the hoop stays visible — and because the mat is a *different fill*
/// rather than just empty space, out-of-hoop stitches read as sitting off the fabric.
/// That is how the user learns the boundary exists before export tells them.
private struct StageFieldView: View {
    let transform: StageTransform

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Canvas { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)), with: .color(StageChrome.outsideField)
            )

            let hoop = transform.viewRect(of: StageGeometry.box)
            context.fill(Path(hoop), with: .color(StageChrome.hoopField))
            context.stroke(
                Path(hoop),
                with: .color(StageChrome.hoopOutline),
                lineWidth: contrast == .increased ? 2 : StageChrome.hoopLineWidth
            )
        }
        // Decorative: the caption below states the hoop's size, which is everything this
        // shape carries. Same reasoning as `StagePlaceholderView`'s outline.
        .accessibilityHidden(true)
    }
}
