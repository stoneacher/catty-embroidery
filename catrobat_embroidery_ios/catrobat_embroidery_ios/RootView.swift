import Samples
import SwiftUI

/// The app's root, adaptive by size class from the start (ADR-010).
///
/// Compact reaches the stage sequentially through a `NavigationStack`; regular
/// shows the list and the stage side by side with the stage on the **detail**
/// side. Deciding this now rather than "adding iPad support later" is the ADR's
/// whole point — retrofitting a split layout onto a stack-shaped app means
/// rewriting the navigation model, not adding a branch.
///
/// **Skeleton fidelity only.** There is no selection, no editor and no run
/// control here: US-304 owns picking a sample, US-305 the renderer, US-306 the
/// run lifecycle. What this story owns is that the shell exists, adapts, is
/// localized, and genuinely links the engine.
///
/// **Known cost: a size-class change discards navigation state.** The `if`
/// swaps one container for the other, so an iPad window resized from regular to
/// compact (Split View, Slide Over, or a rotation on a smaller iPad) tears down
/// the `NavigationSplitView` and builds a fresh, empty `NavigationStack` — the
/// user lands back on the list. Accepted at skeleton fidelity, where the only
/// destination is a placeholder and nothing is lost but a position. It stops
/// being acceptable the moment there is a *selection* to lose, which is US-304,
/// and the fix belongs there rather than here: hoist the selection and the path
/// into an `@Observable` view model owned above this view, so both containers
/// read the same state instead of each owning their own. Pinned in ADR-023 so
/// the swap is not mistaken for a finished adaptive layout.
struct RootView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        // Tested for `.regular`, not for `.compact`, so that a **`nil`** size
        // class — an environment SwiftUI has not resolved — falls to the stack.
        // This is an iPhone-first app (ROADMAP), so the sequential layout is the
        // safe default; the earlier `== .compact` inverted that and handed an
        // unknown environment the split. (In-loop review.)
        if horizontalSizeClass == .regular {
            NavigationSplitView {
                sampleList
                    .navigationTitle(Text(.rootTitle))
                    .navigationBarTitleDisplayMode(.inline)
            } detail: {
                StagePlaceholderView()
            }
        } else {
            NavigationStack {
                sampleList
                    .navigationTitle(Text(.rootTitle))
                    .navigationBarTitleDisplayMode(.inline)
                    .navigationDestination(for: StageDestination.self) { _ in
                        StagePlaceholderView()
                    }
            }
        }
    }

    /// The bundled samples, in `SampleLibrary.all`'s presentation order.
    ///
    /// A private computed property rather than its own type: US-304 replaces
    /// this body with `SamplePickerView` and adds the selection model, so giving
    /// it a name now would create a type that exists only to be deleted.
    ///
    /// Rows carry no `NavigationLink` — a row that navigates *is* selection, and
    /// selection is US-304's. Compact reaches the stage through the separate
    /// link below, which keeps "sequential navigation works" provable today
    /// without inventing a selection model this story would have to unpick.
    private var sampleList: some View {
        List {
            Section {
                ForEach(SampleLibrary.all) { sample in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sample.displayName)
                            .font(.headline)
                        Text(sample.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text(.rootSamplesHeader)
            }

            // `!= .regular`, matching `body`'s test exactly rather than its
            // negation. Written as `== .compact` these two disagree when the size
            // class is `nil`: `body` renders the stack (correct) while this row
            // disappears, leaving the stage unreachable. The two conditions are
            // one decision and must be spelled the same way.
            if horizontalSizeClass != .regular {
                Section {
                    NavigationLink(value: StageDestination.stage) {
                        Text(.stageTitle)
                    }
                }
            }
        }
    }
}

/// The single navigation destination the skeleton has.
///
/// A named type rather than a `Bool` or the sample itself, because
/// `navigationDestination(for:)` keys on the type: when US-304 pushes a chosen
/// sample and US-306 adds a run, each gets its own case here rather than
/// overloading one flag.
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
    RootView()
}
