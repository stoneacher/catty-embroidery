import StagePreview
import SwiftUI

/// The drawn stage: the hoop, the design, the needle — and the gestures that inspect them.
///
/// **Split out of `StageView` because that file had 43 lines left before SwiftLint's hard
/// 400** (CI runs `--strict`, so the default `file_length` warning is an error). This was the
/// coherent seam: everything here is about *looking at* the design, where what remains in
/// `StageView` is about the design's state and what to say when there is none.
///
/// **No decision in this file is made by comparing transforms**, which is US-307's first
/// criterion at the width it finally holds. Everything the frame needs — what to draw with,
/// what the raster may be keyed on, whether anything is in flight, where a gesture moves from —
/// is one call to `StageInteraction`, in the package, under `swift test`.
///
/// It did not start that way. The first version spread that state across a `@GestureState` of
/// live values, a `@State` animation, a `@State` generation token, the committed zoom and three
/// derived expressions, and answered each question by comparing values. The cross-vendor review
/// found a defect in that arrangement in six consecutive rounds — four of them the *same*
/// mistake, asking "is an interaction happening?" of a value rather than of the lifecycle — so
/// the arrangement was replaced rather than patched a seventh time. What is left here is the
/// part SwiftUI must own: an optional whose presence is the gesture, and two conversions on the
/// way in (`CGFloat` → `Double`, `UnitPoint` → two `Double`s) that keep ADR-022's boundary
/// checkable.
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

    @Binding var interaction: StageInteraction

    /// The gesture in flight, or `nil`.
    ///
    /// **Its presence *is* the gesture's lifecycle**, which is the whole reason it is
    /// `@GestureState`: SwiftUI sets it while fingers are down and clears it when the gesture
    /// ends, including one the system cancels for a call or a backgrounding. Every earlier
    /// version of this view inferred "is a gesture happening" from a *value* instead — whether
    /// two transforms were equal, or whether the gesture's own numbers were still their
    /// defaults — and the cross-vendor review found a defect in that inference in four separate
    /// rounds. An optional cannot be wrong in that way.
    ///
    /// The values inside are absolute since the gesture began, because that is what SwiftUI
    /// delivers; nothing here accumulates them.
    @GestureState private var gesture: StageGesture?

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
            // One question, one answer, and it lives in the package: what to draw with, what the
            // raster may be keyed on, and whether anything is in flight at all. The view no
            // longer decides any of that by comparing transforms.
            // **The shim is what makes the fit animation an animation.** A `StageTransform` is
            // not animatable and neither is a `Canvas`'s drawing closure, so `withAnimation`
            // around a mutation of `interaction` animates nothing at all — the reset snaps. An
            // `Animatable` view whose `animatableData` is the progress is the one thing SwiftUI
            // will interpolate, and its body then re-strokes the canvas at each step, which is
            // also what lets a zoom-out reveal content the previous frame had off-screen.
            //
            // Deleting it during the interaction-layer rewrite silently turned the reset into a
            // snap, and no test could see it because they only ever observed progress 0 and 1
            // (Codex round 7).
            SettlingProgress(progress: interaction.settlingProgress) { animated in
                let render = interaction.rendering(
                    gesture: gesture, fitting: fitted, in: viewport, settlingAt: animated
                )

                ZStack {
                    StageFieldView(transform: render.current)
                    renderer.makeBody(
                        display: display, transform: render, needle: needle, viewport: viewport
                    )
                }
                // **The mat, painted behind the canvas rather than inside it.**
                //
                // `StageFieldView` fills the canvas with the mat, but only across the canvas's
                // own bounds; a design panned far enough leaves the field's edge visible, and
                // before this the pane's grouped-background grey showed through (reported by
                // Sebastian from the running app).
                .background(StageChrome.outsideField)
                // Grabbable across the whole slot rather than only where ink was stroked.
                .contentShape(Rectangle())
                // **The handlers live inside the shim so they can see `animated`.**
                //
                // The model's stored progress jumps to 1 the instant `withAnimation` runs; only
                // this closure receives the interpolated value. A handler outside it would
                // interrupt the animation at its *destination*, snapping the stage from what the
                // user can see to the fit before their gesture applied (Codex round 8).
                // Re-creating the gestures per animation frame costs nothing a run does not
                // already cost — `body` re-evaluates once per batch throughout a run, and
                // gestures are values.
                .gesture(inspectGesture(viewport: viewport, fitted: fitted, settlingAt: animated))
                // **A separate modifier, not part of the composition above.** The drag's default
                // 10 pt minimum distance is what lets these coexist — a double tap never moves,
                // so the drag never claims it. Measured, not assumed: building with
                // `DragGesture(minimumDistance: 0)` made the double-tap a byte-for-byte no-op.
                .onTapGesture(count: 2) { resetToFit(fitting: fitted, settlingAt: animated) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(StageAccessibility.label(designName: designName))
                .accessibilityValue(
                    StageAccessibility.value(
                        summary: summary,
                        state: runState,
                        magnification: interaction.magnification(
                            gesture: gesture, fitting: fitted, in: viewport
                        )
                    )
                )
                .accessibilityHint(StageAccessibility.hint(for: runState))
                .accessibilityAddTraits(.isImage)
                // Criterion 7: zoom without gestures, for VoiceOver and Switch Control.
                .accessibilityAdjustableAction { direction in
                    adjust(direction, fitting: fitted, in: viewport, settlingAt: animated)
                }
                // **Required rather than a nicety.** Double-tap-to-fit is unreachable with
                // VoiceOver running — a double tap is VoiceOver's own activate gesture — and
                // Switch Control has no double tap at all. Without this, a user who zooms in
                // has no way back, which would make criterion 7 a trap instead of a feature.
                .accessibilityAction(named: Text(.stageCanvasAccessibilityActionFit)) {
                    resetToFit(fitting: fitted, settlingAt: animated)
                }
            }
        }
    }

    // MARK: - Gestures

    /// Pinch and pan **simultaneously**, folded in once when the gesture ends.
    ///
    /// `.updating` only records what SwiftUI reports; every decision about what that *means* —
    /// whether it is live, what it moves from, whether it changed anything — belongs to
    /// `StageInteraction` and is tested there.
    private func inspectGesture(
        viewport: ViewSize,
        fitted: StageTransform,
        settlingAt progress: Double
    ) -> some Gesture {
        MagnifyGesture()
            .simultaneously(with: DragGesture())
            .updating($gesture) { value, state, _ in
                state = Self.reading(value)
            }
            .onEnded { value in
                interaction.commit(
                    Self.reading(value), fitting: fitted, in: viewport, settlingAt: progress
                )
            }
    }

    /// SwiftUI's composed gesture value as the package's own type.
    ///
    /// **One function, used by both callbacks**, because the live frame and the commit reading
    /// the same event two different ways is precisely the class of bug this story spent six
    /// review rounds on. The conversions are explicit — `CGFloat` → `Double`, a `UnitPoint`'s
    /// two components, a `CGSize`'s two — so no CoreGraphics or SwiftUI type crosses ADR-022's
    /// boundary, and the isolation test can see that it does not.
    private static func reading(
        _ value: SimultaneousGesture<MagnifyGesture, DragGesture>.Value
    ) -> StageGesture {
        StageGesture(
            magnification: Double(value.first?.magnification ?? 1),
            anchorUnitX: Double(value.first?.startAnchor.x ?? 0.5),
            anchorUnitY: Double(value.first?.startAnchor.y ?? 0.5),
            panX: Double(value.second?.translation.width ?? 0),
            panY: Double(value.second?.translation.height ?? 0)
        )
    }

    // MARK: - Programmatic transform changes

    /// Double-tap, and the "Fit to Hoop" accessibility action.
    ///
    /// Animates a `Double` and lets the canvas re-stroke at each step, rather than sliding an
    /// already-rendered layer: a reset from a zoomed-in view is a zoom *out*, which by
    /// definition brings content into frame that the canvas never drew. The bake key stays on
    /// the committed transform throughout, so the settled raster is rebuilt once, at the end.
    ///
    /// Reduce Motion passes `nil`, which is a legal animation meaning "instantly", so one call
    /// site serves both branches with no branch of its own.
    private func resetToFit(fitting fitted: StageTransform, settlingAt progress: Double) {
        // A reset while one is already running takes over from what is on screen, so a repeated
        // double-tap cannot jump backwards past the frame the user is looking at.
        interaction.interrupt(settlingAt: progress)
        guard let settling = interaction.beginSettling(fitting: fitted) else { return }

        // Animating a `Double` *inside* the value is what makes the canvas re-stroke at each
        // step rather than sliding an already-rendered layer — SwiftUI interpolates the
        // progress, `StageInteraction.baseline` turns it into a transform, and the frame is
        // drawn from that. `StageTransform` itself is not animatable, which is why the progress
        // exists at all.
        withAnimation(StageMotion.fitAnimation(reduceMotion: reduceMotion)) {
            interaction.settlingProgressed(to: 1)
        } completion: {
            // The id proves this completion owns the animation it is ending. Being inert when
            // nothing is settling is not enough — without it, a completion from an interrupted
            // animation ends whichever animation happens to be running now.
            interaction.finishSettling(settling)
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
        in viewport: ViewSize,
        settlingAt progress: Double
    ) {
        switch direction {
        case .increment:
            interaction.adjust(.zoomIn, fitting: fitted, in: viewport, settlingAt: progress)
        case .decrement:
            interaction.adjust(.zoomOut, fitting: fitted, in: viewport, settlingAt: progress)
        @unknown default: break
        }
    }
}

/// Re-renders its content at each step of the fit animation.
///
/// The only `Animatable` conformance in the stage, and it exists because SwiftUI will
/// interpolate a `Double` and nothing else here: `StageTransform` is not animatable, and a
/// `Canvas` re-strokes from whatever it is handed rather than tweening. Conforming on the
/// progress gives SwiftUI something it *can* interpolate, and the body turns each interpolated
/// value back into a transform through `StageInteraction`.
///
/// It is passed straight through when nothing is settling, so it costs a closure call at rest.
struct SettlingProgress<Content: View>: View, Animatable {
    var progress: Double
    @ViewBuilder let content: (Double) -> Content

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        content(progress)
    }
}
