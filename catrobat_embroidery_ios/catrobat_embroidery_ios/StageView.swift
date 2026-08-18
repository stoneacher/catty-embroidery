import Samples
import StagePreview
import SwiftUI

/// The stage: the hoop, the design drawn inside and outside it, and what to say when
/// there is nothing to draw yet.
///
/// Replaces `StagePlaceholderView`, which named the selection rather than drawing it and
/// said in its own doc comment that this story would take the `StageView` name.
///
/// Generic over its renderer, per ADR-009: `CanvasStitchRenderer` today, a
/// `MetalStitchRenderer` if US-309's measurements ever demand one, and a recording double
/// in the tests. **The chrome is drawn here rather than by the renderer**, so a
/// replacement renderer inherits the hoop, the fields and the fit for free — and so the
/// one place appearance adapts stays separate from the one place it must not.
struct StageView<Renderer: StagePreviewRenderer>: View {
    /// The chosen design, or `nil` before anything is picked. No default: a defaulted
    /// `nil` would let a call site silently keep the empty state.
    let sample: SampleProgram?

    let display: StitchDisplayList

    /// Where the run is. Drives the transport button's title and symbol, and whether the
    /// stitch-limit notice appears.
    ///
    /// Deliberately **not** the whole `PreviewRunState`: that value also holds the export
    /// model, and a view that took it would retain an up-to-200 000-record
    /// `EmbroideryStream` per frame for nothing. See `RootView.stage`.
    let runState: RunState

    let needle: PreviewNeedle?
    let renderer: Renderer

    /// What the stage holds, in words, for the VoiceOver summary. Taken from the run's phase
    /// rather than recomputed here, because the phase is what guarantees it changes only on
    /// run-state transitions — the story's headline requirement, and one a view recomputing
    /// per body evaluation would break silently.
    let summary: StageSummary

    /// The user's zoom and pan. A binding, because the value is owned by `AppModel` above
    /// `RootView`: ADR-023 records that the size-class swap tears down whichever navigation
    /// container it leaves, and `RootView` builds this view at **two** call sites, so `@State`
    /// here would be two independent zooms that disagree.
    @Binding var zoom: StageZoom

    /// The transport actions. Closures rather than a reference to the view model, so this
    /// view stays testable by hosting it and knows nothing about how a run is driven.
    let onPlay: () -> Void
    let onStop: () -> Void

    private var state: StageContentState {
        .resolving(
            hasSelection: sample != nil,
            hasStitches: !display.isEmpty,
            isRunning: runState.isRunning
        )
    }

    /// The run stopped because it produced more stitches than the preview will draw.
    private var reachedStitchLimit: Bool {
        runState == .finished(.stitchLimitReached)
    }

    /// True when the design reaches outside the 100 mm hoop.
    ///
    /// Compared against `StageGeometry.box`, which bounds nothing in the engine — this is
    /// a *presentation* question, and the only place in M3 that asks it.
    private var leavesTheHoop: Bool {
        guard let bounds = display.bounds else { return false }
        return StageGeometry.fitTarget(including: bounds) != StageGeometry.box
    }

    var body: some View {
        // Order of degradation, and it is deliberate: the canvas gives up space first,
        // then the notices scroll, and the transport button never shrinks.
        VStack(spacing: 12) {
            canvasSlot
            noticeScroller
            StageTransportRow(
                runState: runState,
                hasSelection: sample != nil,
                onPlay: onPlay,
                onStop: onStop
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(sample.map { Text($0.displayName) } ?? Text(.stageTitle))
        .navigationBarTitleDisplayMode(.inline)
        // Twice per run at most, and semantic rather than an impact weight, so it honours
        // the system haptics setting for free. It matters here because the screen's
        // content is a slow animation: a finish can be *felt* instead of watched for.
        .sensoryFeedback(trigger: runState) { _, new in
            switch new {
            case .running: .start
            case .finished: .stop
            case .idle: nil
            }
        }
    }

    /// The canvas keeps an identical frame in all three states, so nothing reflows when
    /// the first batch of stitches lands.
    ///
    /// **No outer `ScrollView`.** `StagePlaceholderView` needed one at AX3–AX5 because it
    /// was a fixed `VStack` of text; a flexible canvas inside a scroll view instead gets
    /// an unbounded height proposal. The lesson that file recorded still applies — but to
    /// the caption block, which is the only thing here that grows with type size.
    private var canvasSlot: some View {
        ZStack {
            switch state {
            case .drawn:
                drawnStage(sample: sample)
            case .notRun, .noSelection:
                emptyStage
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minHeight: 120)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// The drawn state, extracted to `StageCanvas` in US-307.
    ///
    /// **The extraction was forced rather than chosen**: this file was 43 lines below
    /// SwiftLint's hard 400 (CI runs `--strict`) and the gestures plus the accessibility
    /// summary are more than that. The seam is a real one — everything that moved is about
    /// *inspecting* the design, everything left is about its state and its absence.
    private func drawnStage(sample: SampleProgram?) -> some View {
        StageCanvas(
            display: display,
            runState: runState,
            needle: needle,
            renderer: renderer,
            summary: summary,
            designName: sample.map { String(localized: $0.displayName) },
            zoom: $zoom
        )
    }

    /// Both empty states, in the app's existing dashed-hoop idiom.
    ///
    /// **Fully semantic here, and that is consistent rather than an exception to
    /// `StageChrome`'s rule.** The fixed fields exist to protect *design data*; with zero
    /// stitches there is none on screen, and `ContentUnavailableView` uses `label`/
    /// `secondaryLabel`, which would be light-on-light over a fixed light field. So the
    /// fields simply are not drawn until there is something to protect.
    ///
    /// **There is no loading state, and the story asks for that to be said.** Nothing here
    /// is asynchronous: samples are linked rather than decoded (ADR-022), the display list
    /// is in memory, and the raster is produced inside the frame. Even US-306's run enum
    /// has no loading case. So `.notRun` means "not started", which is why its copy names
    /// an action instead of describing progress — and there is no error state either,
    /// because rendering cannot fail: `StageTransform`'s constructor chokepoint degrades a
    /// degenerate viewport or an unrepresentable placement to "off-screen", not to a
    /// failure. The one genuinely user-visible degradation is an ADR-020-rejected
    /// coordinate, drawn but not exportable, and by US-308's own criteria that message
    /// belongs to export.
    private var emptyStage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 2, dash: [6, 6]))
                // Keeps the hoop's own proportions, so the placeholder reads as a hoop
                // rather than as an empty box the width of the pane — which is what it
                // looked like on iPad when this was left to fill the slot. The ratio comes
                // from the box rather than a literal `1` for the reason
                // `StagePlaceholderView` gave: hard-coding it would let this view quietly
                // disagree with `StageGeometry` if the stage ever stopped being square.
                //
                // The *drawn* state deliberately does not do this — there the transform
                // owns fitting, and constraining the canvas would fight it.
                .aspectRatio(
                    StageGeometry.box.width / StageGeometry.box.height, contentMode: .fit
                )
                .accessibilityHidden(true)

            if state == .notRun {
                ContentUnavailableView(
                    String(localized: .stageReadyTitle),
                    systemImage: "play.circle",
                    description: Text(.stageReadyDescription)
                )
            } else {
                ContentUnavailableView(
                    String(localized: .stageEmptyTitle),
                    systemImage: "circle.dashed",
                    description: Text(.stageEmptyDescription)
                )
            }
        }
    }

    /// The caption and both notices, in a scroll view **whose content is all text**.
    ///
    /// This is the distinction `StagePlaceholderView` recorded and US-305 half applied: a
    /// flexible canvas inside a scroll view gets an unbounded height proposal and must
    /// never be wrapped, but a fixed-ideal *text* block must be, or an AX5 pane squeezes it
    /// into truncation. `.basedOnSize` means it does not bounce or read as scrollable until
    /// it genuinely overflows.
    ///
    /// The transport row is deliberately **outside** it: a screen's primary action must not
    /// be reachable only by scrolling.
    private var noticeScroller: some View {
        ScrollView(.vertical) {
            VStack(spacing: 4) {
                Text(Self.hoopSizeDescription)
                    .font(.caption)

                if leavesTheHoop {
                    // Beyond the story's acceptance criteria, deliberately (Sebastian's
                    // call). The criteria make the overflow *visible* — unclipped, and the
                    // fit zooms out — but both cues are sight-only, and nothing else in M3
                    // reports it: US-308 gates export on `assembledStream().count > 1`,
                    // which is hoop-independent. Without this line a VoiceOver user is
                    // never told at all.
                    //
                    // Not an error: the design still draws in full and still exports.
                    // The title/icon closure form, not `Label(_:systemImage:)`: the latter
                    // takes a `StringProtocol`, which would mean resolving the resource to
                    // a `String` here and losing the `Text`-level localisation.
                    Label {
                        Text(.stageOutsideHoop)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                    .font(.footnote)
                }

                if reachedStitchLimit {
                    limitNotice
                }
            }
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        // Without this, a height-constrained proposal makes `Text` ellipsise instead of
        // wrapping — the same guard `SamplePickerView`'s rows and the old placeholder
        // both needed.
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Why the run stopped, and only for the one ending that needs saying.
    ///
    /// `.programFinished` and `.stoppedByUser` explain themselves — the design ran out, or
    /// the user pressed the button — and in both cases the button's own title changes to
    /// "Play Again", which is the cue the accessibility criterion relies on.
    /// `.stitchLimitReached` is the one ending with no cause on screen, and a design that
    /// simply stopped is indistinguishable from a bug.
    ///
    /// **`display.count`, not `RunBudget.maxStitchesPerRun`.** They are different numbers:
    /// `step()` returns one atomic batch the driver cannot split, so the final frame
    /// overshoots the cap — and without any global bound once several scripts run. The
    /// count is what is on screen; the cap is an implementation detail the user never
    /// agreed to.
    ///
    /// `stop.circle`, not the `exclamationmark.triangle` above: both notices can be visible
    /// at once (an out-of-hoop `forever` design), and two identical triangles carrying
    /// different meanings is worse than no icon. It also echoes the transport symbol the
    /// user just pressed, and this is not a warning — the stitches shown are real and the
    /// design still exports.
    ///
    /// It lives in the *scrolling* region rather than beside the button: at AX5 this
    /// sentence is three or four lines, and in the pinned row it would compete for space
    /// the button must not lose. Adjacency — visual and in VoiceOver order — survives
    /// either way.
    private var limitNotice: some View {
        Label {
            Text(.stageRunLimitNotice(display.count))
        } icon: {
            Image(systemName: "stop.circle")
        }
        .font(.footnote)
    }

    /// "Hoop 100 mm × 100 mm" — moved here verbatim from `StagePlaceholderView`.
    ///
    /// `usage: .asProvided` is deliberate: the default lets the formatter pick the
    /// locale's preferred unit and rendered this as "10 cm × 10 cm", which is
    /// arithmetically right and wrong for the domain — ADR-007 defines the stage in
    /// millimetres, DST is a millimetre-based format, and machine vendors specify hoops
    /// in millimetres. The number and the unit abbreviation are still localized; only the
    /// *choice* of unit is pinned.
    ///
    /// Computed rather than stored, because both the measurement formatting and the
    /// catalog lookup depend on a locale that can change while the app runs.
    static var hoopSizeDescription: String {
        let side = Measurement(value: StageGeometry.sideInMillimetres, unit: UnitLength.millimeters)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided))
        return String(localized: LocalizedStringResource.stageHoopSize(side, side))
    }
}

#Preview("Nothing selected") {
    NavigationStack {
        StageView(
            sample: nil,
            display: StitchDisplayList(),
            runState: .idle,
            needle: nil,
            renderer: CanvasStitchRenderer(),
            summary: .empty,
            zoom: .constant(StageZoom()),
            onPlay: {},
            onStop: {}
        )
    }
}

#Preview("Selected, not yet run") {
    NavigationStack {
        StageView(
            sample: SampleLibrary.all.first,
            display: StitchDisplayList(),
            runState: .idle,
            needle: nil,
            renderer: CanvasStitchRenderer(),
            summary: .empty,
            zoom: .constant(StageZoom()),
            onPlay: {},
            onStop: {}
        )
    }
}
