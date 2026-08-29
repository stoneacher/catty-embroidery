import StagePreview
import SwiftUI

/// The caption, every notice the stage has to make, and the design-name field — the one
/// region of the screen that scrolls.
///
/// **Extracted from `StageView` (US-308)**, which was 43 lines below SwiftLint's hard 400
/// before export added a notice and a text field to it. The seam is a real one: everything
/// here is *text about* the design, everything left in `StageView` is the design itself and
/// its absence.
///
/// The order of degradation this belongs to is deliberate and set by the caller: the canvas
/// gives up space first, then these notices scroll, and the transport row never shrinks.
/// `.basedOnSize` means the region does not bounce or read as scrollable until it genuinely
/// overflows, and the transport row stays deliberately **outside** it — a screen's primary
/// action must not be reachable only by scrolling.
///
/// The name field arrives as a **slot** rather than as three more stored properties, for one
/// reason that decides it: `@FocusState.Binding` can only be produced by a view that declares
/// the `@FocusState`, so taking the field's bindings here would force this view to become a
/// focus owner it has no other use for — and the *commit* those bindings drive is a side
/// effect belonging to the caller. As a slot, this view stays what it says it is: an
/// arrangement of text.
struct StageNotices<NameField: View>: View {
    let display: StitchDisplayList

    /// Only `.finished(.stitchLimitReached)` is read, but the whole state is taken so the
    /// predicate stays here rather than becoming a fourth boolean for the caller to compute.
    let runState: RunState

    /// Whether the design reaches outside the hoop. A *presentation* question, answered by
    /// the caller against `StageGeometry`; nothing in the engine bounds anything.
    let leavesTheHoop: Bool

    /// What export has to say, or `nil` when it has nothing to add.
    ///
    /// Deliberately narrower than the share control's accessibility hint, and
    /// `ExportControl.Readiness.notice` is where that narrowing is decided and tested: the
    /// states a sighted user can resolve by looking — nothing selected, not yet run, still
    /// running, an unfinished name — are already explained by the empty states, the transport
    /// button's own title and the field's error line. Repeating them here would be four
    /// redundant lines competing for the space the canvas gives up first.
    let exportNotice: LocalizedStringResource?

    @ViewBuilder let nameField: () -> NameField

    /// The run stopped because it produced more stitches than the preview will draw.
    private var reachedStitchLimit: Bool {
        runState == .finished(.stitchLimitReached)
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 4) {
                Text(Self.hoopSizeDescription)
                    .font(.caption)

                if leavesTheHoop {
                    outsideHoopNotice
                }

                if reachedStitchLimit {
                    limitNotice
                }

                if let exportNotice {
                    exportNoticeLine(exportNotice)
                }

                nameFieldBlock
            }
            .frame(maxWidth: .infinity)
            // **On the content, not on the `ScrollView`.** It sat on the scroller until
            // US-308 (`StageView.swift:243`), and there it inverted the intent: a
            // `ScrollView` handed a `nil` height proposal reports its content's ideal height,
            // and `fixedSize` then makes it refuse anything smaller — so under pressure the
            // region grew and clipped instead of scrolling, defeating the documented "then
            // the notices scroll" degradation step. Here it does what it was written for:
            // `Text` wraps rather than ellipsising under a height-constrained proposal.
            .fixedSize(horizontal: false, vertical: true)
        }
        .scrollBounceBehavior(.basedOnSize)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }

    /// Beyond US-307's acceptance criteria, deliberately (Sebastian's call). The criteria make
    /// the overflow *visible* — unclipped, and the fit zooms out — but both cues are
    /// sight-only, and nothing else in M3 reports it: US-308 gates export on
    /// `assembledStream().count > 1`, which is hoop-independent. Without this line a VoiceOver
    /// user is never told at all.
    ///
    /// Not an error: the design still draws in full and still exports. The title/icon closure
    /// form, not `Label(_:systemImage:)`: the latter takes a `StringProtocol`, which would
    /// mean resolving the resource to a `String` here and losing the `Text`-level
    /// localisation.
    private var outsideHoopNotice: some View {
        Label {
            Text(.stageOutsideHoop)
        } icon: {
            Image(systemName: "exclamationmark.triangle")
        }
        .font(.footnote)
    }

    /// Why the run stopped, and only for the one ending that needs saying.
    ///
    /// `.programFinished` and `.stoppedByUser` explain themselves — the design ran out, or the
    /// user pressed the button — and in both cases the button's own title changes to "Play
    /// Again", which is the cue the accessibility criterion relies on. `.stitchLimitReached`
    /// is the one ending with no cause on screen, and a design that simply stopped is
    /// indistinguishable from a bug.
    ///
    /// **`display.count`, not `RunBudget.maxStitchesPerRun`.** They are different numbers:
    /// `step()` returns one atomic batch the driver cannot split, so the final frame
    /// overshoots the cap — and without any global bound once several scripts run. The count
    /// is what is on screen; the cap is an implementation detail the user never agreed to.
    ///
    /// `stop.circle`, not the `exclamationmark.triangle` above: both notices can be visible at
    /// once (an out-of-hoop `forever` design), and two identical triangles carrying different
    /// meanings is worse than no icon. It also echoes the transport symbol the user just
    /// pressed, and this is not a warning — the stitches shown are real and the design still
    /// exports.
    private var limitNotice: some View {
        Label {
            Text(.stageRunLimitNotice(display.count))
        } icon: {
            Image(systemName: "stop.circle")
        }
        .font(.footnote)
    }

    /// Why the design cannot be shared, for the reasons a sighted user has no other way to
    /// learn. The same catalog entry the disabled control speaks as its hint, so the two
    /// cannot drift.
    ///
    /// A third distinct glyph, following the rule the two notices above already set: this one
    /// names *sharing*, so neither of the others can be mistaken for it.
    private func exportNoticeLine(_ notice: LocalizedStringResource) -> some View {
        Label {
            Text(notice)
        } icon: {
            Image(systemName: "square.and.arrow.up.trianglebadge.exclamationmark")
        }
        .font(.footnote)
        // **Opted out of the block's `.secondary`, after an in-loop review.** The other two
        // notices are commentary on a design that is fine; this one says the design cannot
        // leave the app, and it was rendering in the same chrome grey as "Hoop 100 mm ×
        // 100 mm" while the name field's smaller problem got full contrast. `.primary`
        // rather than a colour: the icon already carries the meaning, so nothing here
        // depends on colour alone.
        .foregroundStyle(.primary)
    }

    /// The field, opted out of the two styles the notices above depend on.
    ///
    /// `.secondary` is right for captions and wrong for an input: a field's own label and its
    /// error line are content, not chrome, and at reduced contrast they are the two things a
    /// user needs most. `.multilineTextAlignment(.center)` is likewise a caption style — a
    /// wrapped label above a left-aligned field would centre itself over it. `.leading`
    /// rather than `.trailing` because it mirrors in RTL, the argument `SamplePickerView`
    /// already makes.
    private var nameFieldBlock: some View {
        nameField()
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }

    /// "Hoop 100 mm × 100 mm" — moved here verbatim from `StageView`, which took it verbatim
    /// from `StagePlaceholderView`.
    ///
    /// `usage: .asProvided` is deliberate: the default lets the formatter pick the locale's
    /// preferred unit and rendered this as "10 cm × 10 cm", which is arithmetically right and
    /// wrong for the domain — ADR-007 defines the stage in millimetres, DST is a
    /// millimetre-based format, and machine vendors specify hoops in millimetres. The number
    /// and the unit abbreviation are still localized; only the *choice* of unit is pinned.
    ///
    /// Computed rather than stored, because both the measurement formatting and the catalog
    /// lookup depend on a locale that can change while the app runs.
    static var hoopSizeDescription: String {
        let side = Measurement(value: StageGeometry.sideInMillimetres, unit: UnitLength.millimeters)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided))
        return String(localized: LocalizedStringResource.stageHoopSize(side, side))
    }
}

#Preview("Every notice at once") {
    StageNotices(
        display: StitchDisplayList(),
        runState: .finished(.stitchLimitReached),
        leavesTheHoop: true,
        exportNotice: ExportControl.Readiness.tooFewStitches.notice
    ) {
        Text(.stageNameLabel)
    }
    .padding()
}
