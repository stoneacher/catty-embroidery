import Foundation
import StagePreview

/// What VoiceOver says about the stage: the label that names it, the value that describes
/// what it holds, and the hint that says what can be done to it.
///
/// **A pure mapping to `String`, not modifiers on a view**, for the reason `RunControl`
/// already gives for the transport button: nothing can read a rendered accessibility value
/// back, so a criterion asserted only through `.accessibilityValue(…)` has no test. Here the
/// strings are values, and `StageAccessibilityTests` asserts them directly.
///
/// Everything user-facing goes through the String Catalog and is composed *through* it — the
/// separators between the parts are catalog entries too, because "a, b, c" is punctuation a
/// translator must be able to change, and in several languages must.
enum StageAccessibility {
    /// Names the element. Stable across a whole run, which is what an accessibility label is
    /// for: it is read every time focus lands, and a label that moved would make the element
    /// feel like a different one.
    ///
    /// **The design name lives here rather than in the value**, and that is a considered
    /// deviation from criterion 5's wording ("a summary value: design name, stitch count,
    /// …"). The summary the criterion describes is label *plus* value, and putting the name
    /// in the value would have it re-spoken on every value change — after every zoom step,
    /// and at both ends of every run. It is also already the navigation title, so on iPad it
    /// is announced when the detail column takes focus.
    static func label(designName: String?) -> String {
        guard let designName, !designName.isEmpty else {
            return String(localized: .stageCanvasAccessibilityLabel)
        }
        return String(localized: .stageCanvasAccessibilityLabelNamed(designName))
    }

    /// Describes what the stage holds.
    ///
    /// **Numbers appear only when they are final**, which is how criteria 5 and 6 are
    /// reconciled. Criterion 5 wants the counts and the size; criterion 6 forbids updating
    /// them except on a run-state transition. Taken together literally, the value would be
    /// computed once at `idle → running` — when the display list is empty and there are no
    /// bounds at all — and would then say "0 stitches" for the entire run while the design
    /// visibly stitched. So a running stage says that it is stitching, and a finished one
    /// says what it made. Nothing is lost: criterion 6 makes mid-run counts unobtainable
    /// either way.
    ///
    /// **The zoom level comes first once the user has zoomed**, and that is the other
    /// deviation. VoiceOver re-reads an element's *value* after each adjustable action, so a
    /// value that could not change would leave the zoom action with no feedback at all — an
    /// accessibility failure in the one feature added for the users who cannot pinch.
    /// Criterion 6's substance is "never per batch", and a zoom step is user-initiated and
    /// discrete; putting it first means the part that changed is heard before the rest, which
    /// the user can swipe past.
    static func value(summary: StageSummary, state: RunState, magnification: Double) -> String {
        let described = describing(summary: summary, state: state)
        guard let zoom = zoomPhrase(magnification: magnification) else { return described }
        return String(localized: .stageCanvasAccessibilityValueZoomed(zoom, described))
    }

    /// What the stage can be asked to do. Varies by run state, per criterion 5.
    ///
    /// Hints are spoken last, after a delay, and can be switched off entirely (VoiceOver →
    /// Verbosity → Speak Hints) — which is why the run state is carried in the *value* as
    /// well rather than only here.
    ///
    /// **`.idle` shares the finished hint rather than owning one, because it is unreachable
    /// here.** The canvas exists only in `StageContentState.drawn`, which needs
    /// `hasStitches || isRunning`, and the sole route to `.idle` is `PreviewRunState.reset()`
    /// — which empties the display list on its way. So `.idle` with something drawn cannot
    /// happen. A third catalog entry did ship briefly; it was a full sentence heading for ~75
    /// Crowdin translators that no user could ever hear, and it is deleted rather than
    /// documented (`swift-code-reviewer`). The switch stays exhaustive, so a fourth `RunState`
    /// case would still be a compile error here.
    static func hint(for state: RunState) -> String {
        switch state {
        case .running: String(localized: .stageCanvasAccessibilityHintRunning)
        case .idle, .finished: String(localized: .stageCanvasAccessibilityHintFinished)
        }
    }

    /// The design, in words, once it is finished — or the fact that it is still being made.
    private static func describing(summary: StageSummary, state: RunState) -> String {
        guard !state.isRunning else {
            return String(localized: .stageCanvasAccessibilityValueStitching)
        }
        // Composed **through** the catalog rather than concatenated: each count carries its
        // own plural variations, and the separators between the three parts are a catalog
        // entry of their own, because "a, b, c" is punctuation a translator must be able to
        // change — and in several languages must.
        return String(
            localized: .stageCanvasAccessibilityValue(
                String(localized: .stageCanvasAccessibilityStitches(summary.stitchCount)),
                String(localized: .stageCanvasAccessibilityColors(summary.colorCount)),
                size(of: summary)
            )
        )
    }

    /// `nil` at the fit, so the value stays clean until the user has actually zoomed.
    ///
    /// Rounded to whole per cent before the comparison, not after: at 100.4 % the phrase
    /// would read "Zoom 100 per cent", which says the stage is fitted while claiming it is
    /// not. A tolerance on the *displayed* value is the only one that cannot contradict
    /// itself.
    private static func zoomPhrase(magnification: Double) -> String? {
        guard magnification.isFinite, magnification > 0 else { return nil }
        let percent = (magnification * 100).rounded()
        guard percent != 100 else { return nil }

        let formatted = (percent / 100).formatted(.percent.precision(.fractionLength(0)))
        return String(localized: .stageCanvasAccessibilityZoom(formatted))
    }

    /// "98.6 millimetres by 98.6 millimetres".
    ///
    /// **Each length carries its own unit, spelled out.** The story's example states the unit
    /// once — "98.6 by 98.6 millimetres" — which reads well in English and is not composable
    /// anywhere else: unit names inflect with the number and with grammatical case, and their
    /// position moves, so a catalog entry with the word `millimetres` in it can only ever be
    /// right for one of the two numbers. Handing `Measurement.FormatStyle` both lengths makes
    /// the agreement ICU's problem rather than the translator's, which is what a repo
    /// shipping ~75 languages through Crowdin needs.
    ///
    /// `.wide` rather than the hoop caption's `.abbreviated`: this string exists only to be
    /// spoken, and VoiceOver's expansion of "mm" is not guaranteed across locales and voices —
    /// "m m", letter by letter, is the failure mode. **Abbreviated for the eye, wide for the
    /// ear.**
    ///
    /// `usage: .asProvided` for the same reason the hoop caption pins it: the default lets the
    /// locale pick, and a US reader would hear inches for a millimetre-based machine format.
    /// The explicit precision is needed too — without it the style will happily say
    /// "98.568 millimetres", where the figure this story verifies is one decimal.
    private static func size(of summary: StageSummary) -> String {
        String(
            localized: .stageCanvasAccessibilitySize(
                spoken(summary.widthInMillimetres), spoken(summary.heightInMillimetres)
            )
        )
    }

    private static func spoken(_ millimetres: Double) -> String {
        Measurement(value: millimetres, unit: UnitLength.millimeters)
            .formatted(
                .measurement(
                    width: .wide,
                    usage: .asProvided,
                    numberFormatStyle: .number.precision(.fractionLength(0 ... 1))
                )
            )
    }
}
