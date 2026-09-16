import StagePreview

/// The stage's spoken strings, computed once per distinct state rather than once per frame.
///
/// **ADR-028 named this and handed it to US-309, which did not take it.** Every body evaluation
/// of `StageCanvas` rebuilds the label, the hint and the value, and the value runs
/// `Measurement.FormatStyle` twice with a `.wide` unit style — tens of microseconds per call,
/// on the path US-310 ground down to a 16.667 ms median. US-313b is the story that makes that
/// path hot (a manipulation that tracks properly is one users hold, and hold while looking), so
/// it is the story that takes the cache.
///
/// **The cost is where the story did not say it was, and the correction matters for the key.**
/// `describing(summary:state:)` returns early while a run is `.running`, so the two measurement
/// formats are unreachable mid-run: they are on the *finished-design* path, which is precisely
/// the path a gesture exercises. Right conclusion, mechanism off by one state.
///
/// **Two keys, not one.** The story specifies `(summary, state, roundedPercent)`. That is wrong
/// twice. It omits `designName`, which the *label* depends on — a memo whose key does not
/// determine its output is unsound whether or not the missing input can currently change. And
/// folding the zoom into one key would invalidate the expensive half on nearly every frame of a
/// pinch, which is the one path the cache exists for. So the description is keyed on
/// `(summary, state)`, constant for a whole manipulation; the label on `designName`; and the
/// zoom phrase — one number format — is simply recomputed, which keeps `zoomPhrase`'s rounding
/// rule the single source of truth instead of re-deriving a rounded percent at the call site.
///
/// **A reference type, and deliberately not `@Observable`.** It is written *during* body
/// evaluation, where a `@State` value type cannot be mutated at all; an observable mutation per
/// frame would invalidate the view that caused it, which is the feedback loop US-309's readout
/// was already caught in once. The precedent is `StageDrawCounter`, written inside a `Canvas`
/// drawing closure for the same reason and non-observable for the same one. Unlike that counter
/// this is an **instance** held by the view, not a global: process-wide mutable state would be
/// shared across tests that run in parallel.
///
/// Caching localized output is safe for the process's lifetime because iOS relaunches the app
/// when the language or region changes.
@MainActor
final class StageAccessibilityMemo {
    /// What VoiceOver says about the stage, as one value.
    ///
    /// A named type rather than a tuple: the three strings are read together, and three
    /// positional components is where a call site starts getting them in the wrong order.
    struct Spoken: Equatable {
        let label: String
        let value: String
        let hint: String
    }

    /// What the expensive half depends on, and nothing else.
    private struct DescriptionKey: Equatable {
        let summary: StageSummary
        let state: RunState
    }

    private var descriptionKey: DescriptionKey?
    private var described = ""
    private var hint = ""

    /// `String??` is not a typo: the outer optional is "nothing cached yet", the inner one is
    /// the design name's own absence, and collapsing them would recompute the anonymous label
    /// on every frame before a design is picked.
    private var labelKey: String??
    private var label = ""

    /// How many times the expensive half has actually run. Production bookkeeping the tests
    /// read, in the shape ADR-028's Codex round 7 settled on — the generation token came back
    /// *inside* the value, "where, unlike the `@State` counter it replaced, a test can reach
    /// it". Counting is what makes "computed once per distinct state" an assertion rather than
    /// a claim, and no shared state is needed for it because each view owns its own memo.
    private(set) var descriptionComputations = 0
    private(set) var labelComputations = 0

    /// What VoiceOver should say about the stage right now.
    ///
    /// The three strings are returned together because they are read together, once per body
    /// evaluation, and because handing back one at a time would invite three cache lookups
    /// where one suffices.
    func strings(
        designName: String?,
        summary: StageSummary,
        state: RunState,
        magnification: Double
    ) -> Spoken {
        if labelKey != .some(designName) {
            label = StageAccessibility.label(designName: designName)
            labelKey = .some(designName)
            labelComputations += 1
        }

        let key = DescriptionKey(summary: summary, state: state)
        if descriptionKey != key {
            described = StageAccessibility.describing(summary: summary, state: state)
            hint = StageAccessibility.hint(for: state)
            descriptionKey = key
            descriptionComputations += 1
        }

        return Spoken(
            label: label,
            value: StageAccessibility.value(describing: described, magnification: magnification),
            hint: hint
        )
    }
}
