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

    /// The transport actions. Closures rather than a reference to the view model, so this
    /// view stays testable by hosting it and knows nothing about how a run is driven.
    let onPlay: () -> Void
    let onStop: () -> Void

    private var state: StageContentState {
        .resolving(hasSelection: sample != nil, hasStitches: !display.isEmpty)
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
        VStack(spacing: 12) {
            canvasSlot
            captionBlock
            transportRow
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(sample.map { Text($0.displayName) } ?? Text(.stageTitle))
        .navigationBarTitleDisplayMode(.inline)
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
                drawnStage
            case .notRun, .noSelection:
                emptyStage
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minHeight: 120)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// `GeometryReader` is where the viewport comes from, and it is the reason the wiring
    /// tests have to host this view: its closure does not run when `body` is merely read.
    private var drawnStage: some View {
        GeometryReader { proxy in
            let viewport = ViewSize(proxy.size)
            let transform = StageTransform.fitting(
                StageGeometry.fitTarget(including: display.bounds), in: viewport
            )

            ZStack {
                StageFieldView(transform: transform)
                renderer.makeBody(
                    display: display, transform: transform, needle: needle, viewport: viewport
                )
            }
            // US-307 owns the real summary — design name, stitch count, colours, size in
            // mm — and its adjustable actions. Until then this is a **name with no
            // value**: a placeholder value would be a lie, and leaving it unset means
            // there is nothing to un-say later.
            //
            // Deliberately not `accessibilityHidden`. The canvas is the whole content of
            // the screen, so hiding it would make the screen read as empty and the design
            // undiscoverable; the caption does not carry what the canvas carries (which
            // is why hiding the *hoop shape* in `StagePlaceholderView` was correct and
            // this would not be); and a hidden element cannot receive US-307's
            // adjustable action, so hiding would silently defer work this comment makes
            // explicit instead.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(.stageCanvasAccessibilityLabel))
            .accessibilityAddTraits(.isImage)
        }
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

    /// Outside the canvas, so semantic — and the only text that scales with type size.
    private var captionBlock: some View {
        VStack(spacing: 4) {
            Text(Self.hoopSizeDescription)
                .font(.caption)

            if leavesTheHoop {
                // Beyond the story's acceptance criteria, deliberately (Sebastian's
                // call). The criteria make the overflow *visible* — unclipped, and the
                // fit zooms out — but both cues are sight-only, and nothing else in M3
                // reports it: US-308 gates export on `assembledStream().count > 1`,
                // which is hoop-independent. Without this line a VoiceOver user is never
                // told at all.
                //
                // Not an error: the design still draws in full and still exports.
                // The title/icon closure form, not `Label(_:systemImage:)`: the latter
                // takes a `StringProtocol`, which would mean resolving the resource to a
                // `String` here and losing the `Text`-level localisation.
                Label {
                    Text(.stageOutsideHoop)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .font(.footnote)
            }
        }
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        // Without this, a height-constrained proposal makes `Text` ellipsise instead of
        // wrapping — the same guard `SamplePickerView`'s rows and the old placeholder
        // both needed.
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The transport button, and the notice explaining a run that stopped itself.
    ///
    /// **Below the caption rather than in the toolbar**, for three reasons that are not
    /// interchangeable with a `.toolbar` item: thumb reach on an iPhone-first app; it
    /// appears in the definition-of-done screenshots in both size classes; and the ≥ 44 pt
    /// criterion is provable **by construction** here — an explicit `frame` plus
    /// `contentShape` — where a toolbar item's hit area is the system's to decide and
    /// nothing in a test could measure it.
    private var transportRow: some View {
        VStack(spacing: 8) {
            if reachedStitchLimit {
                // Beyond the story's acceptance criteria, on the same footing as US-305's
                // out-of-hoop caption (Sebastian's call). Without it a `forever` design
                // simply stops, and neither a sighted nor a VoiceOver user is told why.
                //
                // Not an error styling: the stitches shown are real and the design still
                // exports.
                Text(.stageRunLimitNotice(display.count))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            transportButton
        }
    }

    private var transportButton: some View {
        let appearance = RunControl.appearance(for: runState, hasSelection: sample != nil)

        return Button {
            if runState.isRunning {
                onStop()
            } else {
                onPlay()
            }
        } label: {
            // The visible title **is** the accessibility label — one catalog entry cannot
            // disagree with itself, where a separate `.accessibilityLabel` beside a title
            // is free to drift from it. The title/icon closure form rather than
            // `Label(_:systemImage:)`, whose `StringProtocol` overload would force
            // resolving the resource to a `String` here and lose `Text`-level
            // localisation.
            Label {
                Text(appearance.title)
            } icon: {
                Image(systemName: appearance.symbol)
            }
            // Grows with type size and wraps rather than truncating at AX5 — the same
            // guard the caption block needs.
            .fixedSize(horizontal: false, vertical: true)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderedProminent)
        .disabled(!appearance.isEnabled)
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

#Preview("Nothing selected") {
    NavigationStack {
        StageView(
            sample: nil,
            display: StitchDisplayList(),
            runState: .idle,
            needle: nil,
            renderer: CanvasStitchRenderer(),
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
            onPlay: {},
            onStop: {}
        )
    }
}
