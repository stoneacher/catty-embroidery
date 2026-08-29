import StagePreview
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
/// done: the selection and the compact path live in `AppModel`, owned by
/// `WindowRootView` above this view, so both containers read the same state
/// instead of each owning their own. **Above this view, and specifically *not*
/// on the `App`** — state declared there is shared by every scene, which on
/// iPad let one window drive another (Codex round 1). ADR-023 asks for
/// ownership above `RootView`; it does not ask for App scope, and the two are
/// not interchangeable. `AppModel`'s doc comment lists what still does not survive
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
                // The sidebar shows the selection, because the detail column
                // beside it *is* the selection. The stack does not — see
                // `SamplePickerView.showsSelection`.
                SamplePickerView(model: model, showsSelection: true)
            } detail: {
                // The detail column ignores `path` entirely: it shows the
                // selection, or the empty state before there is one. Two
                // representations of "which sample" would be two things able to
                // disagree after a Back.
                stage
            }
        } else {
            NavigationStack(path: $model.path) {
                SamplePickerView(model: model, showsSelection: false)
                    .navigationDestination(for: StageDestination.self) { _ in
                        stage
                    }
            }
        }
    }

    /// Both call sites build the stage the same way, so they cannot drift apart.
    ///
    /// **US-305's `.task(id: model.selection)` drain is gone**, and nothing replaced it
    /// here. The run is started by the user pressing play, and it is discarded by
    /// `AppModel.select(_:)` — deliberately not by a view modifier keyed on the
    /// selection. `.task(id:)` and `.onChange(of:initial:)` both re-fire when this view
    /// rebuilds its navigation container after a horizontal size-class change (ADR-023),
    /// so either would wipe a finished design on an iPad window resize.
    ///
    /// The needle comes from `visibleNeedle`, which **is** the "only while running" rule
    /// rather than a place that reimplements it. It was spelled out here as a conditional,
    /// and the test that claimed to pin it recomputed the same conditional in its own body —
    /// so the test stayed green if this line dropped the condition entirely
    /// (`swift-code-reviewer`). A needle parked on a finished design would imply the machine
    /// is still working on it.
    ///
    /// The display list and the run state are handed over **separately, never as the
    /// whole `PreviewRunState`**. That value also holds the export model — an
    /// `EmbroideryStream` of up to 200 000 records — and putting it into the view
    /// hierarchy would make every frame retain a copy of an array nothing on screen
    /// reads. US-308 takes the export model from the view model directly.
    private var stage: some View {
        // A local `@Bindable` because `AppModel.exporter` is a `let` reference — the identity
        // never changes, so `$model.exporter` would be projecting a constant. `@Bindable`
        // projects the *observable class's* own properties instead, which is what `name`
        // needs to be: a two-way binding into the object that also validates it.
        @Bindable var exporter = model.exporter

        return StageView(
            sample: model.selection?.sample,
            display: model.runner.run.display,
            runState: model.runner.run.state,
            needle: model.runner.run.visibleNeedle,
            renderer: CanvasStitchRenderer(),
            // From the run's phase, which is what makes it change on run-state transitions
            // only. Recomputing it here — the obvious alternative — would rebuild it on every
            // body evaluation, i.e. once per batch, which is exactly what US-307's headline
            // criterion forbids and what makes VoiceOver unusable.
            summary: model.runner.run.summary,
            interaction: $model.interaction,
            // Resolved here, from the four facts only the model holds. `ExportControl` is
            // where the precedence between them lives and is tested — a view choosing among
            // them inline would have no test at all, which is the argument `RunControl`
            // already makes for the transport button.
            exportReadiness: ExportControl.readiness(
                hasSelection: model.selection != nil,
                runState: model.runner.run.state,
                eligibility: model.runner.run.exportEligibility,
                name: model.exporter.validatedName,
                exportState: model.exporter.state
            ),
            designName: $exporter.name,
            nameValidation: model.exporter.validatedName,
            // `model.play()` rather than `runner.play(program)`: starting a run must also
            // discard the file the *last* run prepared, and that pairing belongs with the
            // model that owns both. See `AppModel.play()`.
            onPlay: { model.play() },
            onStop: { model.runner.stop() },
            onCommitName: { model.commitName() }
        )
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
