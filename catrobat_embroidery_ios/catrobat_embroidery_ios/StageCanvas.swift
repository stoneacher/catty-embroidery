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
                let render: StageRenderTransform = current == committed
                    ? .settled(committed)
                    : .live(bake: committed, current: current)

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
        guard live != LiveGesture() else { return committed }
        var moved = zoom
        moved.overriding(committed)
        return moved.previewing(
            magnification: Double(live.magnification),
            anchor: ViewPoint(unitX: live.anchor.x, unitY: live.anchor.y, in: viewport),
            pan: ViewPoint(live.pan),
            fitting: fitted
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
                if let pinch = value.first {
                    state.magnification = pinch.magnification
                    state.anchor = pinch.startAnchor
                }
                if let pan = value.second {
                    state.pan = pan.translation
                }
            }
            .onEnded { value in
                // Cancels any fit animation in flight, so its completion cannot undo this
                // commit. Both halves matter: the token invalidates the pending completion,
                // and clearing `settling` stops a half-finished spring drawing over a
                // transform that has just moved underneath it.
                settleGeneration &+= 1
                settling = nil

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

}

/// A gesture's absolute state since it began. See `StageCanvas.live`.
struct LiveGesture: Equatable {
    var magnification: CGFloat = 1
    var anchor: UnitPoint = .center

    /// The drag's translation, **including the recognizer's threshold distance**.
    ///
    /// An earlier version subtracted the first callback's translation so the content would
    /// not jump by the ~10 pt threshold when a pan starts. That was wrong in a way only
    /// measurement found: `@GestureState` has already reset by the time `onEnded` runs, so
    /// the origin read there was always `nil` and the *commit* used the raw translation while
    /// the *live* offset had subtracted it — moving the content forward by the threshold at
    /// finger-lift, which is a worse artefact than the one it was avoiding and the opposite
    /// of what the comment claimed (`swift-code-reviewer`, measured at 101 pt committed for a
    /// 101 pt drag whose live offset had shown 91).
    ///
    /// Not subtracting anywhere is the fix: live and committed are then the *same* number by
    /// construction rather than by two pieces of code agreeing. The price is the jump the
    /// subtraction existed to avoid, now paid at pan **start**, where it reads as the drag
    /// catching rather than as the content slipping after the finger stops.
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

/// A fit animation in flight: where it started, where it is going, and how far along it is.
struct SettlingFit: Equatable {
    let from: StageTransform
    let to: StageTransform
    var progress: Double
}

/// Re-renders its content at an interpolated transform for each step of an animation.
///
/// **The reason this exists rather than a `.scaleEffect`.** SwiftUI can only animate values it
/// can interpolate, and a `StageTransform` is not one — `Canvas` re-strokes from whatever it is
/// handed. Conforming to `Animatable` on a plain `Double` gives SwiftUI something it *can*
/// interpolate, and the body then asks the package for the transform at that point. The result
/// is that the canvas is genuinely re-drawn at each step, which is what lets a zoom-out reveal
/// content that was previously outside the canvas's bounds.
///
/// `progress` is passed straight through when no animation is running (`from == to`), so this
/// costs a closure call and nothing else in the common case.
struct StageInterpolatedCanvas<Content: View>: View, Animatable {
    var progress: Double
    let from: StageTransform
    let to: StageTransform
    @ViewBuilder let content: (StageTransform) -> Content

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        content(from.interpolated(to: to, progress: progress))
    }
}
