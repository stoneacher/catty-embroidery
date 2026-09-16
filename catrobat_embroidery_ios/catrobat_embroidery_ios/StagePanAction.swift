import StagePreview
import SwiftUI

extension StagePanDirection {
    /// What VoiceOver, Switch Control and Voice Control call this direction.
    ///
    /// App-side rather than in the package because the words come from the String Catalog, which
    /// belongs to the app target (ADR-022). Two words, verb first, matching "Fit to Hoop" — and
    /// the "Pan" prefix stays because a bare "Left" or "Up" collides with Voice Control's own
    /// vocabulary ("Swipe up", "Scroll down"), while "Pan" is not a system command.
    var accessibilityActionName: LocalizedStringResource {
        switch self {
        case .left: .stageCanvasAccessibilityActionPanLeft
        case .right: .stageCanvasAccessibilityActionPanRight
        case .up: .stageCanvasAccessibilityActionPanUp
        case .down: .stageCanvasAccessibilityActionPanDown
        }
    }
}

/// One directional pan accessibility action: the name and the movement, from one direction.
///
/// **It is a modifier rather than four closures in the view because of what went wrong without
/// it.** The first version spelled the name and the step at each of four call sites —
/// `.accessibilityAction(named: Text(.stageCanvasAccessibilityActionPanLeft)) { pan(.left, …) }`
/// — which leaves the join between the two spellings free to be wrong. It was proven free:
/// `swift-code-reviewer` rewired "Pan Left" to `pan(.right)`, "Pan Right" to `pan(.left)` and
/// both vertical actions to `pan(.down)`, and **the whole app suite stayed green**. The catalog
/// test compares the four *strings* to each other and the package test proves `.left` is
/// camera-relative, but nothing joined a name to a case, and the test the story planned for that
/// was dropped as an accessibility-tree walk — the technique US-307 deleted for CI flakiness.
///
/// Taking both from one `direction` makes the mismatch unrepresentable, which is better than a
/// test for it: there is no longer a wrong version to catch.
///
/// The four still appear as four modifiers in `StageCanvas` rather than a loop, because the
/// order they are declared in is the order the Actions rotor offers them, and "Fit to Hoop" has
/// to stay first as the recovery from everything the other four can do.
struct StagePanAction: ViewModifier {
    let direction: StagePanDirection
    @Binding var interaction: StageInteraction
    let fitted: StageTransform
    let viewport: ViewSize

    /// The fit animation's visible progress, from the `SettlingProgress` shim — so an action
    /// taken mid-animation takes over at what is on screen rather than at the destination.
    let settlingProgress: Double

    func body(content: Content) -> some View {
        content.accessibilityAction(named: Text(direction.accessibilityActionName)) {
            // **Deliberately not animated**, for the reason the adjustable action is not: an
            // assistive user stepping across their design gains nothing from a spring, and what
            // is spoken afterwards should describe where the stage is rather than where it is
            // heading.
            interaction.panned(
                by: direction.step(in: viewport), fitting: fitted, settlingAt: settlingProgress
            )
        }
    }
}
