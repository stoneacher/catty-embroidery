import SwiftUI

/// The share affordance: hands the prepared `.dst` to the system share sheet, or says why it
/// cannot (US-308).
///
/// **Two controls in one place, and the disabled one is not an oversight.** A `ShareLink`
/// needs its item at construction time, so there is nothing to render when no file has been
/// prepared — but simply omitting the control would make it appear and disappear as runs
/// start and end, moving everything below it and leaving a VoiceOver or Switch Control user
/// with no element to land on and therefore nowhere to be told *why*. A disabled `Button`
/// with the same title keeps the place, keeps the focus target, and carries the hint.
///
/// Every question about *whether* and *what to say* is answered by `ExportControl.Readiness`,
/// which is a value precisely so that it can be tested: nothing can read a rendered
/// `.accessibilityHint` back out of a hosted view. This view re-derives none of it.
///
/// **US-312 adds a caption under the button**: DST files carry no thread colours. It is read
/// by VoiceOver as the element straight after the button rather than being combined into it —
/// combining would replace the button's label (its title, below) and push a disabled
/// control's reason behind a sentence that is not a reason.
struct StageExportRow: View {
    let readiness: ExportControl.Readiness

    var body: some View {
        VStack(spacing: 4) {
            button
            if let note = readiness.threadColorNote {
                // The screen's plain-fact style — the hoop-size caption's, which is `.caption`
                // and inherits `.secondary` from `StageNotices`' block — and deliberately none of
                // a notice's: no glyph, no colour. The export is correct;
                // this is information. Outside `.disabled`, so it is not dimmed with the
                // button and does not read as the reason it is dimmed.
                Text(note)
                    .font(.caption)
                    // **Capped at AX1**, the story's Dynamic Type bar, and a measured choice
                    // rather than a reflex (Sebastian, 2026-09-27). At AX5 an uncapped caption
                    // grows to five lines in a pinned row and the Share button's label spills
                    // out of its own background. That is on top of a squeeze that predates
                    // this story: on `main` at AX5 the design-name field already disappears
                    // behind the pinned rows, which is backlog US-319's stage-chrome overflow
                    // entry and not something a caption can fix. Secondary text may stop
                    // scaling under the HIG; the button and the field it gates may not.
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    // Wraps rather than truncating at large type sizes; the row is pinned, so
                    // every line comes out of the canvas, which gives up space first.
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder private var button: some View {
        let styled = control
            // `.bordered`, **not** `.borderedProminent`: `StageTransportRow` is this
            // screen's one prominent control, and `RunControl` records why two prominent
            // titled buttons break at AX5. A second prominent button would also compete
            // with the primary action for the eye at exactly the moment the run ends.
            .buttonStyle(.bordered)
            // Derived from `readiness` rather than from `shareURL` a second time, so the
            // two branches below cannot fall out of step with enablement.
            .disabled(!readiness.isEnabled)

        if let hint = readiness.hint {
            styled.accessibilityHint(Text(hint))
        } else {
            // `ready` explains itself and `noSelection` never renders, so there is nothing
            // to add. Not a placeholder string: ADR-028 records what shipping copy for an
            // unreachable state costs at ~75 translators a time.
            styled
        }
    }

    @ViewBuilder private var control: some View {
        if let url = readiness.shareURL {
            ShareLink(item: DSTDesign(url: url), preview: SharePreview(url.lastPathComponent)) {
                title
            }
        } else {
            // No action, and none is reachable: this branch exists only while
            // `readiness.isEnabled` is false, and the `.disabled` above is applied to both.
            Button {} label: {
                title
            }
        }
    }

    /// The visible title **is** the accessibility label — one catalog entry cannot disagree
    /// with itself, where a separate `.accessibilityLabel` beside a title is free to drift.
    /// No hand-added `.isButton` trait either: both branches are real buttons and already
    /// carry it.
    ///
    /// The title/icon closure form rather than `Label(_:systemImage:)`, whose
    /// `StringProtocol` overload would force resolving the resource to a `String` here and
    /// lose `Text`-level localisation.
    private var title: some View {
        Label {
            Text(.stageExportShare)
        } icon: {
            Image(systemName: "square.and.arrow.up")
        }
        // Explicit, so no ancestor style can collapse this to an icon-only button and take
        // the visible title — and therefore the accessibility label — with it.
        .labelStyle(.titleAndIcon)
        .multilineTextAlignment(.center)
        // Grows with type size and wraps rather than truncating at AX5.
        .fixedSize(horizontal: false, vertical: true)
        // The ≥ 44 pt floor, built the way `StageTransportRow` builds it: on the *label*, so
        // the bordered background inherits it, and `minHeight` never `height`, because
        // Dynamic Type may only make it larger.
        .frame(maxWidth: .infinity, minHeight: RunControl.minimumTouchTarget)
        // Makes the whole rectangle hittable rather than the glyph-and-text ink.
        .contentShape(Rectangle())
    }
}

#Preview("Ready") {
    StageExportRow(readiness: .ready(URL.temporaryDirectory.appendingPathComponent("square-coil.dst")))
        .padding()
}

#Preview("Disabled — still running") {
    StageExportRow(readiness: .running)
        .padding()
}
