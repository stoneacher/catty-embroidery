import StagePreview
import SwiftUI

/// What the transport button looks like and says, as a pure function of the run.
///
/// **A value rather than logic inside `StageView`, because otherwise the story's
/// "accessibility labels that change with state" criterion has no test.** Nothing
/// can read a rendered `Button`'s label back out of a hosted view, so a mapping
/// built inline in `body` is only checkable by looking at a screenshot — and a
/// screenshot cannot show what VoiceOver would say.
///
/// One button rather than separate play and stop buttons: a single transport
/// control is the HIG-idiomatic form, it makes the changing label natural instead
/// of bolted on, and it avoids the AX5 wrapping problem two side-by-side titled
/// buttons would create.
enum RunControl {
    /// The visible title doubles as the accessibility label. Deliberately: one
    /// catalog entry cannot disagree with itself, whereas a separate
    /// `accessibilityLabel` is free to drift from the title next to it.
    struct Appearance {
        let symbol: String
        let title: LocalizedStringResource
        let isEnabled: Bool
    }

    static func appearance(for state: RunState, hasSelection: Bool) -> Appearance {
        switch state {
        case .idle:
            Appearance(symbol: "play.fill", title: .stageRunPlay, isEnabled: hasSelection)
        case .running:
            // Enabled regardless of `hasSelection`: a run in flight must always be
            // stoppable. The combination cannot arise today — nothing clears a
            // selection — but a control the user cannot use to stop a machine
            // metaphor is the wrong way to be wrong.
            Appearance(symbol: "stop.fill", title: .stageRunStop, isEnabled: true)
        case .finished:
            // One title for all three completion reasons: to this button they mean the
            // same thing — the run is over, and pressing it starts a new one. Why it
            // ended is the notice line's job, not the control's.
            //
            // Distinct from `.idle`'s title on purpose. "Play" for both would leave a
            // VoiceOver user unable to tell a design that has finished from one that
            // has not started, which is the only cue they have.
            Appearance(symbol: "play.fill", title: .stageRunPlayAgain, isEnabled: hasSelection)
        }
    }
}
