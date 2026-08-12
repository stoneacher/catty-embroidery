// `Observation`, not `SwiftUI`: the model is the app's state, and nothing here
// needs a view type. Keeping SwiftUI out of this file is what lets the tests
// exercise it as a plain object.
import Observation
import Samples

/// The app's state above the navigation containers: what can be picked, what is
/// picked, and how deep the compact stack is.
///
/// One instance per window, owned by `WindowRootView` — not by the `App`, whose
/// state every scene would share. See that view for why; the short version is
/// that this app supports multiple iPad windows, and a selection is a per-window
/// decision.
///
/// **Owning this above `RootView` is what makes the size-class swap lossless**,
/// and it is the fix US-303 deferred to this story by name (`RootView`'s own doc
/// comment, and ADR-023). `RootView` branches on the horizontal size class and
/// swaps one navigation container for another, tearing down whichever it leaves;
/// anything either container owned goes with it. Until now that cost only a
/// scroll position, because there was nothing to select. There is now.
///
/// What survives an iPad window resize across the boundary: the selection —
/// identity *and* generation — and the compact stack depth. What honestly does
/// not, listed rather than glossed:
///
/// - scroll position in the list and in the detail column, which SwiftUI owns
///   inside the container being destroyed;
/// - `NavigationSplitViewVisibility`, which resets to `.automatic`. Hoistable in
///   one property and deliberately not hoisted: `.automatic` is the right state
///   on re-entry, so the property would exist only to be preserved;
/// - in-flight transitions across the swap.
@MainActor
@Observable
final class AppModel {
    /// What the picker lists.
    ///
    /// A pass-through today, and the single seam M5 replaces when the real
    /// project list arrives (create/rename/duplicate/delete). Routing the view
    /// through it rather than letting the view read `SampleLibrary.all` directly
    /// is the entire reason M5 is an edit here instead of an edit to the view.
    var samples: [SampleProgram] {
        SampleLibrary.all
    }

    /// The chosen sample, or `nil` before the first tap.
    ///
    /// `private(set)` so every mutation goes through `select(_:)` and the
    /// generation can never be skipped — an assignment that bypassed it would
    /// reintroduce exactly the no-op this story exists to forbid.
    private(set) var selection: SampleSelection?

    /// The compact navigation stack's path.
    ///
    /// `var`, because `NavigationStack(path:)` writes back on Back and on the
    /// interactive swipe. A typed array rather than `NavigationPath` because it
    /// is `Equatable` and a test can assert the whole value; `NavigationPath`
    /// exposes only `count`.
    var path: [StageDestination] = []

    /// `@ObservationIgnored` on purpose: bumping the counter is bookkeeping, not
    /// state anyone renders. Without it, one selection would produce two
    /// observable mutations, which is the opposite of the discipline US-306 is
    /// held to ("exactly one observable mutation per batch").
    @ObservationIgnored private var nextGeneration = 0

    /// Selects `sample` and shows the stage.
    ///
    /// Never a no-op, even for the sample already selected: the fresh generation
    /// makes the new value unequal to the old one, which is what lets a later
    /// consumer treat any selection as "start over" (US-306).
    ///
    /// The path is **assigned**, not appended to. Appending would stack a second
    /// stage on the first, so Back would return to a stage rather than to the
    /// list.
    func select(_ sample: SampleProgram) {
        selection = SampleSelection(sample: sample, generation: nextGeneration)
        nextGeneration += 1
        path = [.stage]
    }

    /// Whether `sample` is the current selection — the row highlight and the
    /// `.isSelected` VoiceOver trait.
    ///
    /// Compares ids, not samples. `SampleProgram`'s synthesized `==` drags the
    /// whole `Program` tree along, and this runs for every row on every body
    /// evaluation.
    func isSelected(_ sample: SampleProgram) -> Bool {
        selection?.sample.id == sample.id
    }
}
