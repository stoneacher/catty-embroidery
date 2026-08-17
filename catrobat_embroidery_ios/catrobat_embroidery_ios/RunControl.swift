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
        // Red-phase stub.
        _ = state
        _ = hasSelection
        return Appearance(symbol: "play.fill", title: .stageRunPlay, isEnabled: false)
    }
}
