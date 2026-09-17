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
/// the arrangement was replaced rather than patched a seventh time.
///
/// **US-313b moved the input layer out again**, and this paragraph used to end by describing
/// what it left behind — "an optional whose presence is the gesture, and two conversions on the
/// way in". Both are gone: the `@GestureState` is a `@State StageManipulation` fed by a UIKit
/// recogniser pair (`StageManipulationCatcher`), and the only conversion left in the app is
/// `CGPoint` → `ViewPoint`, in `StageTransform+CoreGraphics`. What this file owns now is the
/// *presentation* — the shim that animates, the accessibility surface, and where the catcher
/// sits in the modifier chain.
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

    /// The manipulation in flight, tracked by the package.
    ///
    /// **Replaces a `@GestureState`, and the property it gave up has to be replaced too.** That
    /// wrapper's presence *was* the gesture's lifecycle: SwiftUI set it while fingers were down
    /// and cleared it for a gesture the system cancelled. `StageManipulation` holds the same
    /// property deliberately — `isLive` is asked of the recognisers' states, never inferred
    /// from values — and the clearing that came free now has a named test on both sides of the
    /// boundary, because a coordinator does not get it for nothing.
    ///
    /// View-local, exactly as the `@GestureState` was: touch delivery is per-view, and the
    /// size-class change that destroys this view also cancels the recognisers. `interaction` is
    /// the value that needs `AppModel`, because `RootView` builds the stage at two call sites.
    @State private var manipulation = StageManipulation()

    /// The spoken strings, computed once per distinct state rather than once per body.
    ///
    /// `@State` of a reference type, which is what lets it be written *during* body evaluation
    /// — see `StageAccessibilityMemo`, which explains why it is neither a value nor observable.
    @State private var spoken = StageAccessibilityMemo()

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
                // **The one read of the tracker per frame.** It is a `@State` captured by the
                // closure the shim calls, so during a fit animation — when only the shim's body
                // re-runs — this is the value from the last outer body evaluation.
                //
                // What makes that safe is **not** "a manipulation and an animation cannot
                // coexist", which is what this comment first claimed and is false: the
                // coordinator's `beginManipulating` ends the animation in the *model*, while the
                // `withAnimation` transaction interpolating the shim keeps running and its
                // completion still fires (`swift-code-reviewer`, Q3). What actually holds is
                // narrower and stronger: every mutation of `manipulation` goes through the
                // `@State` setter, so the outer body is re-evaluated and this closure is rebuilt
                // before the next render — and `StageInteraction.baseline(fitting:settlingAt:)`
                // ignores the progress once the phase is no longer `.settling`.
                let gesture = manipulation.gesture(in: viewport)
                let render = interaction.rendering(
                    gesture: gesture, fitting: fitted, in: viewport, settlingAt: animated
                )
                let says = spoken.strings(
                    designName: designName,
                    summary: summary,
                    state: runState,
                    magnification: interaction.magnification(
                        gesture: gesture, fitting: fitted, in: viewport
                    )
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
                // **The catcher lives inside the shim, and above the accessibility modifiers.**
                //
                // Inside, because only this closure receives the interpolated progress: the
                // model's stored value jumps to 1 the instant `withAnimation` runs, so a catcher
                // built outside would interrupt an animation at its *destination*, snapping the
                // stage from what the user can see to where it was heading (Codex round 8).
                //
                // Above `.accessibilityElement(children: .ignore)`, because that modifier merges
                // the subtree *below it in the chain*: an overlay attached after it is a sibling
                // of the merged element, and the stage becomes two accessibility elements. That
                // is the one line of this surgery no screenshot can check, and it is why AC8 is
                // an Accessibility Inspector pass rather than a test.
                .overlay {
                    StageManipulationCatcher(
                        snapshot: StageManipulationCatcher.Snapshot(
                            fitted: fitted, viewport: viewport, settlingProgress: animated
                        ),
                        manipulation: $manipulation,
                        interaction: $interaction,
                        onDoubleTap: { point in
                            toggle(about: point, fitting: fitted, settlingAt: animated)
                        },
                        onCommitted: commitRecorder
                    )
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(says.label)
                .accessibilityValue(says.value)
                .accessibilityHint(says.hint)
                .accessibilityAddTraits(.isImage)
                // Criterion 7: zoom without gestures, for VoiceOver and Switch Control.
                .accessibilityAdjustableAction { direction in
                    adjust(direction, fitting: fitted, in: viewport, settlingAt: animated)
                }
                // **Required rather than a nicety.** Double-tap-to-fit is unreachable with
                // VoiceOver running — a double tap is VoiceOver's own activate gesture — and
                // Switch Control has no double tap at all. Without this, a user who zooms in
                // has no way back, which would make criterion 7 a trap instead of a feature.
                // **The completion of what the adjustable action started.** `adjust` anchors on
                // the viewport's centre, so zoom was reachable without gestures and pan was not:
                // a user could reach 3× and still only ever see the middle of their design. Four
                // named directions, spoken rather than gestural, and camera-relative — "Pan
                // Left" moves the view left, so the design's left-hand side comes into sight.
                //
                // Written out rather than looped, because the name and the movement both come
                // from one `direction` (`StagePanAction`) and cannot disagree — the review
                // proved they could when spelled separately here.
                //
                // **Declared in reverse, because the rotor reads them in reverse — measured, not
                // assumed.** The planning pass flagged that SwiftUI's ordering of
                // `.accessibilityAction(named:)` against source order cannot be taken on trust
                // and had to be read off the Accessibility Inspector. It was, on device
                // (2026-09-17): declaring Fit to Hoop first put it **last** in the list, behind
                // all four pans. So the declaration order below is the reverse of the spoken
                // order, and the spoken order is what matters — **Fit to Hoop first**, because
                // it is the recovery from everything the other four can do, and a rotor is
                // traversed one swipe at a time.
                .modifier(panAction(.down, fitting: fitted, in: viewport, settlingAt: animated))
                .modifier(panAction(.up, fitting: fitted, in: viewport, settlingAt: animated))
                .modifier(panAction(.right, fitting: fitted, in: viewport, settlingAt: animated))
                .modifier(panAction(.left, fitting: fitted, in: viewport, settlingAt: animated))
                .accessibilityAction(named: Text(.stageCanvasAccessibilityActionFit)) {
                    resetToFit(fitting: fitted, settlingAt: animated)
                }
            }
        }
    }

    // MARK: - Touches

    /// Counts committed manipulations, in debug builds only.
    ///
    /// Supplied by the view rather than recorded inside the coordinator so that a process-wide
    /// counter is never written by the parallel suites that drive the coordinator directly —
    /// which would let an unrelated test inflate the count a frame-time capture reports.
    private var commitRecorder: (() -> Void)? {
        #if DEBUG
            StageCommitCounter.record
        #else
            nil
        #endif
    }

    // MARK: - Programmatic transform changes

    /// The "Fit to Hoop" accessibility action.
    ///
    /// **No longer the double tap**, which US-313a made a toggle: fitted taps zoom in about the
    /// tapped point, anything else returns to the fit. This stays the unconditional way back,
    /// which is what an assistive user relies on — a double tap is VoiceOver's own activate
    /// gesture, and Switch Control has none at all.
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

    /// The double tap: **fit ↔ ~2× about the tapped point.**
    ///
    /// Maps and Photos zoom *in* where you tapped; the shipped stage only ever reset, which is a
    /// divergence from the apps a user is comparing it against. US-313a shipped the math and
    /// nothing called it — `beginToggle` had no call site in the app until this line — so the
    /// toggle is new behaviour here rather than a re-test of the package.
    ///
    /// Shares `resetToFit`'s animation machinery deliberately: one answer to "what happens when
    /// you interrupt a fit", not one per caller. The interrupt is `beginToggle`'s own, at the
    /// *visible* progress, because a zoom-in's destination is not the fit — interrupting at 1
    /// snapped the stage forward to 2× and then animated back (`/codex-review` round 2).
    private func toggle(
        about point: ViewPoint,
        fitting fitted: StageTransform,
        settlingAt progress: Double
    ) {
        guard let settling = interaction.beginToggle(
            about: point, fitting: fitted, settlingAt: progress
        ) else { return }

        withAnimation(StageMotion.fitAnimation(reduceMotion: reduceMotion)) {
            interaction.settlingProgressed(to: 1)
        } completion: {
            interaction.finishSettling(settling)
        }
    }

    /// One directional pan action, its name and its movement taken from the same `direction`.
    ///
    /// The step and its sign live in the package (`StagePanDirection`), so "Pan Left brings the
    /// left-hand side into view" is a `swift test` assertion rather than a comment here; the
    /// name is joined to the direction in `StagePanAction`, so the two cannot disagree.
    private func panAction(
        _ direction: StagePanDirection,
        fitting fitted: StageTransform,
        in viewport: ViewSize,
        settlingAt progress: Double
    ) -> StagePanAction {
        StagePanAction(
            direction: direction,
            interaction: $interaction,
            fitted: fitted,
            viewport: viewport,
            settlingProgress: progress
        )
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
