import StagePreview
import SwiftUI

/// The transport button: play, stop, play again.
///
/// **Split out of `StageView` because that file crossed SwiftLint's 400-line limit**, and
/// this was the coherent seam: everything here is about *the run*, where the rest of
/// `StageView` is about the design. Extracting the field view instead would have separated
/// the hoop from the canvas that fits to it.
///
/// **Below the caption rather than in the toolbar**, for three reasons a `.toolbar` item
/// cannot supply: thumb reach on an iPhone-first app; it appears in the definition-of-done
/// screenshots in both size classes; and the ≥ 44 pt criterion is provable **by
/// construction** here — an explicit frame plus `contentShape` — where a toolbar item's hit
/// area is the system's to decide and nothing in a test could measure it.
struct StageTransportRow: View {
    let runState: RunState

    /// Whether a design is selected at all, which is what decides enablement.
    let hasSelection: Bool

    let onPlay: () -> Void
    let onStop: () -> Void

    /// Read in exactly one place in this story — the symbol morph below. Named here so
    /// US-307 reuses this gate for its transform springs instead of adding a second one.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let appearance = RunControl.appearance(for: runState, hasSelection: hasSelection)

        return Button(action: toggleRun) {
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
                    // The symbol morph is decoration, so Reduce Motion takes it. The
                    // symbol still *changes* — it just does not animate. This is the one
                    // place US-306 reads the setting, and it is the hook US-307 should
                    // reuse for its transform springs rather than introducing a second,
                    // ungated one.
                    .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
            }
            // Explicit, so no ancestor style can collapse this to an icon-only button and
            // take the visible title — and therefore the accessibility label — with it.
            .labelStyle(.titleAndIcon)
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            // Grows with type size and wraps rather than truncating at AX5 — the same
            // guard the notice block needs.
            .fixedSize(horizontal: false, vertical: true)
            // The ≥ 44 pt floor, and the reason it sits on the *label*:
            // `.borderedProminent` sizes its background from what it is given and only
            // adds padding, so a floor here is a floor on the whole control. `minHeight`
            // and never `height` — Dynamic Type may only make it larger, and a fixed
            // height at AX5 is how a button clips its own title.
            .frame(maxWidth: .infinity, minHeight: RunControl.minimumTouchTarget)
            // Makes the whole rectangle hittable rather than the glyph-and-text ink.
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderedProminent)
        .disabled(!appearance.isEnabled)
        // Keeps its ideal height when the pane is short: the canvas and the notices both
        // yield space before this does.
        .layoutPriority(1)
    }

    /// One button, two meanings. **No `.destructive` role and no red tint on stop**:
    /// stopping keeps the stitches and keeps the design exportable — the whole point of
    /// `RunTermination` — and the catalog comment for `stage.run.stop` already tells
    /// translators to avoid a word implying cancellation. A red button would say in colour
    /// what the string is forbidden to say in words.
    private func toggleRun() {
        if runState.isRunning {
            onStop()
        } else {
            onPlay()
        }
    }
}
