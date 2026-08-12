import SwiftUI

/// The app's root, adaptive by size class from the start (ADR-010).
///
/// Compact reaches the stage sequentially through a `NavigationStack`; regular
/// shows the picker and the stage side by side with the stage on the **detail**
/// side. Deciding this now rather than "adding iPad support later" is the ADR's
/// whole point — retrofitting a split layout onto a stack-shaped app means
/// rewriting the navigation model, not adding a branch.
///
/// **The size-class swap no longer discards the selection.** US-303 shipped this
/// view with an `if` that swaps one container for the other, tearing down
/// whichever it leaves, and recorded the cost as acceptable only while there was
/// nothing to select — with the fix assigned to this story (ADR-023). It is
/// done: the selection and the compact path live in `AppModel`, owned by the
/// `App` above this view, so both containers read the same state instead of each
/// owning their own. `AppModel`'s doc comment lists what still does not survive
/// the swap (scroll positions, split-view column visibility, in-flight
/// transitions) rather than leaving the claim broader than it is.
///
/// What no unit test can prove is that the model is owned *above* the swap —
/// that is proved by construction and by resizing an iPad window across the
/// boundary in the simulator, which is why that check is in this story's
/// definition of done.
struct RootView: View {
    /// `@Bindable` for `$model.path` alone; everything else reads through the
    /// plain reference, which `@Observable` tracks just as well.
    @Bindable var model: AppModel

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        // Tested for `.regular`, not for `.compact`, so that a **`nil`** size
        // class — an environment SwiftUI has not resolved — falls to the stack.
        // This is an iPhone-first app (ROADMAP), so the sequential layout is the
        // safe default; the earlier `== .compact` inverted that and handed an
        // unknown environment the split. (In-loop review.)
        if horizontalSizeClass == .regular {
            NavigationSplitView {
                SamplePickerView(model: model)
            } detail: {
                // The detail column ignores `path` entirely: it shows the
                // selection, or the empty state before there is one. Two
                // representations of "which sample" would be two things able to
                // disagree after a Back.
                StagePlaceholderView(sample: model.selection?.sample)
            }
        } else {
            NavigationStack(path: $model.path) {
                SamplePickerView(model: model)
                    .navigationDestination(for: StageDestination.self) { _ in
                        StagePlaceholderView(sample: model.selection?.sample)
                    }
            }
        }
    }
}

/// The single navigation destination the skeleton has.
///
/// A named type rather than a `Bool` or the sample itself, because
/// `navigationDestination(for:)` keys on the type: when US-306 adds a run, it
/// gets its own case here rather than overloading one flag.
///
/// **It stays valueless, correcting what US-303's comment anticipated.** That
/// comment expected US-304 to push the chosen sample into the path. Doing so
/// would make the path a second source of truth for "which sample", able to
/// disagree with `AppModel.selection` after a Back, and the generation token
/// that makes re-selection meaningful could not live coherently in two places.
/// The destination closure reads the selection instead. One owner.
enum StageDestination: Hashable {
    case stage
}

// One preview, no size-class overrides — the canvas's own width decides, which
// is the only thing that tells the truth here.
//
// Two overridden previews were removed after the in-loop review *measured* what
// they showed: forcing `.regular` on an iPhone-width canvas does take the
// `NavigationSplitView` branch, but the split view then lays itself out from the
// container's real width and renders **detail only, with the sidebar collapsed
// behind a toggle** — so a preview labelled "Regular" showed neither the sidebar
// nor the compact layout. The `.compact` override was a no-op on the same canvas.
// A preview that misrepresents the layout is worse than no preview, because the
// next author trusts it. Both size classes are covered by the simulator
// screenshots the UI definition of done requires.
#Preview {
    RootView(model: AppModel())
}
