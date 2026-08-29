// `Observation`, not `SwiftUI`: the model is the app's state, and nothing here
// needs a view type. Keeping SwiftUI out of this file is what lets the tests
// exercise it as a plain object.
// The engine, interpreter and preview imports went with the temporary drain US-305
// left here: this file no longer touches a stitch, an interpreter or a display list —
// `RunViewModel` owns all three. Worth noting rather than silently tidying, because
// the narrowing is the point: the app's selection state and the app's run are separate
// concerns again.
//
// **`StagePreview` came back in US-307, and only for `StageInteraction`** — a `Sendable`
// value, not a stitch, an interpreter or a display list, so the narrowing above still holds as
// stated. It is here because the zoom must outlive the ADR-023 container swap and because
// `RootView` builds the stage at two call sites; see `interaction`. Recorded rather than left
// for a reader to notice the comment above had quietly stopped being true.
import Observation
import Samples
import StagePreview

/// The app's state above the navigation containers: what can be picked, what is
/// picked, and how deep the compact stack is.
///
/// One instance per window, owned by `WindowRootView` — not by the `App`, whose
/// state every scene would share. See that view for why; the short version is
/// that this app supports multiple iPad windows, and a selection is a per-window
/// decision.
///
/// **Owning this above `RootView` is what stops the size-class swap discarding
/// the selection** — deliberately not "lossless", which an earlier version of
/// this comment claimed three lines above a list of things it does lose,
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

    /// The run this window's stage shows.
    ///
    /// Owned here — above `RootView` — and deliberately not `@State` in `StageView`.
    /// ADR-023 records that `RootView` swaps one navigation container for another on a
    /// horizontal size-class change and tears down whichever it leaves; a run held
    /// inside either container would be cancelled, and a finished design lost, by an
    /// iPad window resize. That is the hazard US-304 was written to fix, and putting the
    /// run in a view would reintroduce it one story later.
    ///
    /// `let`, not `var`: the identity never changes. Starting over is
    /// `RunViewModel.reset()`, not a new instance, so nothing can be observing the old
    /// one.
    let runner: RunViewModel

    /// The design's name and the file prepared from it (US-308).
    ///
    /// Owned here for the third time for the same ADR-023 reason as `runner` and
    /// `interaction`: a name held as `@State` in the stage would be lost on an iPad window
    /// resize, and — since `RootView` builds the stage at two call sites — would be two
    /// different names that disagree.
    let exporter: ExportViewModel

    /// Both are injectable so tests can supply immediate pacing and a recording writer;
    /// the defaults are what the app runs with.
    init(runner: RunViewModel = RunViewModel(), exporter: ExportViewModel = ExportViewModel()) {
        self.runner = runner
        self.exporter = exporter

        // The export is prepared when the run *ends*, which is what a `ShareLink` needs:
        // it takes its item at construction time, so there is nothing to hand it unless the
        // file already exists. See `ExportViewModel` for why that is forced rather than
        // chosen.
        runner.onRunTerminated = { [weak self] model in
            self?.exporter.prepare(exportModel: model)
        }
        // The other half of the lifecycle, and structural rather than conventional: the
        // prepared file goes whenever the run it describes goes, however that happens.
        runner.onRunDiscarded = { [weak self] in
            self?.exporter.discard()
        }
    }

    /// Starts the selected design from the beginning, throwing away whatever the last run
    /// prepared.
    ///
    /// Round 1 of the cross-vendor review found Play Again leaving `exporter.state ==
    /// .ready(oldURL)` — that URL still holding the *previous* run — while the new run had
    /// already cleared the design. The discard lives on `RunViewModel.onRunDiscarded` rather
    /// than here, because round 2 pointed out that putting it in this method left the
    /// invariant as a convention: `runner.play(_:)` and `runner.reset()` are both reachable
    /// directly. This method now only resolves the selection.
    func play() {
        guard let program = selection?.program else { return }
        runner.play(program)
    }

    /// Rewrites the file under the name the user has just committed.
    ///
    /// Called on submit and on focus loss, **never per keystroke**: the name goes into the
    /// `LA` bytes as well as the file name, so every commit genuinely invalidates the
    /// previous file and a per-keystroke call would write one file per character.
    ///
    /// A no-op before anything has run, which is not merely defensive — there is no design
    /// to serialise, and a file named after one that does not exist is a lie the share
    /// control would then offer.
    func commitName() {
        guard let model = runner.run.exportModel else { return }
        exporter.prepare(exportModel: model)
    }

    /// Where this window's stage is zoomed and panned to, and what is currently happening to
    /// it.
    ///
    /// Owned here for the same ADR-023 reason the run is, plus one this story adds:
    /// `RootView` builds the stage at **two** call sites — the split view's detail column and
    /// the stack's navigation destination — so state held as `@State` in the stage would be
    /// two independent values, and an iPad window resized across the size-class boundary
    /// would show the other one.
    ///
    /// A plain `Sendable` value rather than a second `@Observable` class: it owns no tasks and
    /// no lifecycle, so a reference type would be an abstraction with nothing to justify it.
    var interaction = StageInteraction()

    /// The chosen sample, or `nil` before the first tap.
    ///
    /// `private(set)` so every mutation goes through `select(_:)` and the
    /// generation can never be skipped — an assignment that bypassed it would
    /// reintroduce exactly the no-op this story exists to forbid.
    private(set) var selection: SampleSelection?

    /// The compact navigation stack's path.
    ///
    /// `var`, because `NavigationStack(path:)` writes back on Back and on the
    /// interactive swipe. A typed array rather than `NavigationPath` because a
    /// test can assert the whole value — `NavigationPath` is `Equatable` too, so
    /// the reason is readability of its *contents*, not equality, which an
    /// earlier version of this comment got wrong.
    ///
    /// It is an unrestricted `var`, so the invariant "a non-empty path implies a
    /// selection" is upheld by there being exactly one writer today
    /// (`select(_:)`) and not by the type. A later story that pushes `.stage`
    /// without selecting — a deep link, state restoration — would reach a stage
    /// titled "Stage" showing the empty state. Worth encoding when there is a
    /// second writer; not worth the binding machinery while there is one.
    var path: [StageDestination] = []

    /// `@ObservationIgnored` on purpose: bumping the counter is bookkeeping, not
    /// state anyone renders, and the attribute keeps it out of the observation
    /// graph entirely.
    ///
    /// It is **not** what keeps `select(_:)` to a single notification, which an
    /// earlier version of this comment claimed. Observation is keypath-granular,
    /// so an un-ignored counter would notify only observers that had *read* it,
    /// and nothing reads it — it is `private`. And `select(_:)` mutates two
    /// observed properties anyway (`selection` and `path`), so the "exactly one
    /// observable mutation" discipline US-306 is held to is not a property this
    /// class has ever had. (In-loop review.)
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
    ///
    /// It writes `path` even when the split layout is showing, which ignores it.
    /// That is deliberate rather than a leak: it means a window resized down to
    /// compact opens on the design the user had selected, which is how UIKit's
    /// own split-view collapse behaves.
    /// It also **discards whatever the previous design left on the stage**, and it does
    /// so here rather than in a view. The view-side spellings — `.onChange(of:
    /// initial:)`, `.task(id:)` — re-fire when `RootView` rebuilds a navigation
    /// container after a horizontal size-class change (ADR-023), so on an iPad window
    /// resize they would wipe a design the user had just watched finish. This method
    /// already has exactly one writer; the reset belongs with it.
    func select(_ sample: SampleProgram) {
        selection = SampleSelection(sample: sample, generation: nextGeneration)
        nextGeneration += 1
        path = [.stage]
        // `reset()` discards the run, which fires `onRunDiscarded` and takes the previous
        // design's file with it. Leaving the file would offer a share button that sends the
        // *last* design — the staleness ADR-023 exists to prevent, one layer up.
        runner.reset()
        // **`SampleID.resourceName`, not `sample.displayName`.** `displayName` is a
        // `LocalizedStringResource` from the `Samples` bundle, and "Octagon Rosette" is
        // *exactly* 15 characters in English — so any locale whose translation is one
        // character longer, or not Latin at all, would open this screen already showing a
        // validation error the user did not cause. `resourceName` is ASCII, locale-
        // independent, and already the canonical file stem. It reuses a persistence token as
        // a default machine label, which is defensible precisely because `LA` is a machine
        // label rather than UI copy (ADR-026).
        exporter.name = sample.id.resourceName
        // A new design arrives fitted. Inheriting the previous design's 4× zoom would show a
        // corner of something the user has not seen whole yet — and the zoom was chosen
        // against a fit that no longer applies. Here rather than in an `.onChange`, for the
        // reason the run's reset is here: the view-side spellings re-fire on the ADR-023
        // container rebuild.
        interaction.followFit()
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
