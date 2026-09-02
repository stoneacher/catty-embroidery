import EmbroideryEngine
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
    @Binding var interaction: StageInteraction

    /// What the share affordance offers and, when it offers nothing, why — resolved by
    /// `ExportControl` rather than re-derived here, so the visible notice and the spoken hint
    /// cannot disagree.
    let exportReadiness: ExportControl.Readiness

    /// The design's name, owned by `AppModel` (ADR-023) and edited here.
    @Binding var designName: String

    /// The name's verdict. Passed in rather than computed, so the field, the counter and the
    /// share control all read one value.
    let nameValidation: Result<DesignName, DesignNameProblem>

    /// The transport actions. Closures rather than a reference to the view model, so this
    /// view stays testable by hosting it and knows nothing about how a run is driven.
    let onPlay: () -> Void
    let onStop: () -> Void

    /// Called when the name is committed — on submit and on focus loss, **never per
    /// keystroke**, because the name goes into the `LA` bytes and every commit rewrites the
    /// file.
    let onCommitName: () -> Void

    /// Declared here rather than in `DesignNameField`, because focus *loss* is what triggers
    /// the commit and only the owner of the state can watch for it.
    @FocusState private var isNameFocused: Bool

    private var state: StageContentState {
        .resolving(
            hasSelection: sample != nil,
            hasStitches: !display.isEmpty,
            isRunning: runState.isRunning
        )
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
        // Order of degradation, and it is deliberate: the canvas gives up space first, then
        // the notices scroll, and **both** pinned action rows never shrink. US-308 added the
        // second row; the sentence above used to say "the transport button", singular.
        VStack(spacing: 12) {
            canvasSlot
            notices
            // Above the transport row, not below it: the transport button is this screen's
            // primary action and stays nearest the thumb. `.bordered` against its
            // `.borderedProminent` keeps exactly one prominent control, which is what
            // `RunControl` records as the reason there is one transport button rather than
            // two side-by-side titled ones.
            //
            // Hidden while the name is being edited. At AX4–AX5 with the keyboard raised the
            // two pinned rows plus the canvas floor exceed a short device's height, and there
            // is no outer `ScrollView` to absorb it (`canvasSlot`). You cannot share a name
            // you are still typing, and the keyboard's Done key is the way out.
            if !isNameFocused, sample != nil {
                StageExportRow(readiness: exportReadiness)
            }
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
        // US-309's frame-time readout, for the measurement fixture only. An overlay rather
        // than a row in the chrome, so the stage keeps exactly the layout every other
        // screenshot in this milestone was taken of.
        .overlay(alignment: .bottom) { frameTimeReadout }
    }

    /// Present only in debug builds, and only for the measurement fixture.
    @ViewBuilder private var frameTimeReadout: some View {
        #if DEBUG
        if sample?.id == .us309Synthetic, case .drawn = state {
            FrameTimeReadout()
        }
        #endif
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
            interaction: $interaction
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
            // **Before the overlay, so it hides the dashes and not the words.** Moving it
            // after would take the `ContentUnavailableView` out of the accessibility tree
            // with it, which is the whole content of this state.
            .accessibilityHidden(true)
            // **An overlay rather than a `ZStack` sibling**, which is what actually fixes
            // the cramped text: as siblings the label was sized by the *slot* while the
            // dashes were sized by the aspect-fitted square, so on a pane wider than it is
            // tall the two had different widths and the description ran into — and past —
            // the border. As an overlay the label is bounded by the frame it is drawn
            // inside, so the inset below is measured from the dashes themselves.
            .overlay {
                unavailableView
                    .padding(.horizontal, 24)
            }
    }

    /// Both empty states' content. Extracted only so `emptyStage` stays readable now that
    /// the dashes carry an overlay.
    @ViewBuilder
    private var unavailableView: some View {
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

    /// The caption, the notices and the design-name field, extracted to `StageNotices` in
    /// US-308 — the third extraction this file's 400-line SwiftLint ceiling has forced, after
    /// `StageTransportRow` and `StageCanvas`. The seam is a real one: everything that moved is
    /// *text about* the design, everything left is the design itself and its absence.
    ///
    /// The field is a slot rather than three more parameters on `StageNotices`, because
    /// `@FocusState.Binding` can only come from the view that declares the `@FocusState` —
    /// and the commit it drives belongs here, next to `onCommitName`.
    private var notices: some View {
        StageNotices(
            display: display,
            runState: runState,
            leavesTheHoop: leavesTheHoop,
            exportNotice: exportReadiness.notice
        ) {
            if sample != nil {
                DesignNameField(
                    name: $designName,
                    validation: nameValidation,
                    isFocused: $isNameFocused
                )
                .onSubmit(onCommitName)
            }
        }
        // Focus *loss* is the second commit trigger, and it has to be watched from the owner
        // of the state. Only on losing it: gaining focus commits nothing.
        .onChange(of: isNameFocused) { _, focused in
            if !focused {
                onCommitName()
            }
        }
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
            interaction: .constant(StageInteraction()),
            exportReadiness: .noSelection,
            designName: .constant(""),
            nameValidation: DesignName.validating(""),
            onPlay: {},
            onStop: {},
            onCommitName: {}
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
            interaction: .constant(StageInteraction()),
            exportReadiness: .notRun,
            designName: .constant("OctagonRosette"),
            nameValidation: DesignName.validating("OctagonRosette"),
            onPlay: {},
            onStop: {},
            onCommitName: {}
        )
    }
}
