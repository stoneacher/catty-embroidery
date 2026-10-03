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
import EditorCore
import EmbroideryEngine
import Foundation
import Observation
import ProgramModel
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
        #if DEBUG
            // **Appended here rather than added to `SampleLibrary.all`**, and appended *last*.
            //
            // US-309 needs a 50 000-stitch design reachable in the running app — the frame
            // capture and the screenshots are of the real screen, not of a harness. It needs to
            // be a real `SampleProgram` because the stage's title, its accessibility label and
            // `ExportControl.readiness` all key off a selected sample; a launch-argument path
            // that ran the program without selecting anything would screenshot a
            // half-configured screen.
            //
            // It stays out of the library because five `SamplesTests` suites iterate
            // `SampleLibrary.all` to assert properties of *shipping* content — a checked-in JSON
            // encoding, a DST golden, an ADR-019 threshold screen — and because ROADMAP M3
            // requires the bundled samples to be visually appealing designs "not test shapes".
            //
            // Last, so it can never displace a shipping sample from the top of the picker and
            // every existing screenshot keeps its meaning.
            SampleLibrary.all + [
                SampleProgram(id: .us309Synthetic, program: makeUS309SyntheticProgram())
            ]
        #else
            SampleLibrary.all
        #endif
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

    /// The working program and its history (US-405).
    let editor: EditorViewModel

    /// The saved working program's guard, shared with every other window (US-406).
    let autosave: ProgramAutosave

    /// A saved program found at launch and not opened, until the user has been told.
    private(set) var launchRefusal: ProgramRefusal?

    /// Why the working program is not being saved, or `nil` while it is.
    var saveFailure: ProgramSaveFailure? {
        autosave.failure
    }

    /// The rest are injectable so tests can supply immediate pacing and a recording writer;
    /// the defaults are what the app runs with. `autosave` has no default: it is shared across
    /// windows, so only their owner can supply it, and a default would be silent non-saving.
    init(
        autosave: ProgramAutosave,
        runner: RunViewModel = RunViewModel(),
        exporter: ExportViewModel = ExportViewModel(),
        editor: EditorViewModel = EditorViewModel()
    ) {
        self.runner = runner
        self.exporter = exporter
        self.editor = editor
        self.autosave = autosave

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
        editor.onProgramChanged = { [weak self] in
            self?.programChanged()
        }

        // Launch selects the blank program, opening on its script (US-407) — see `.launch`.
        selection = .launch(generation: nextGeneration)
        nextGeneration += 1
        path = [.script]
    }

    /// What an edit, an undo or a redo (US-408) does to the window (ADR-038) — one handler, so
    /// undoing to P after running Q cannot leave Q's `.dst` offered. **`runner.reset()` and
    /// nothing else from `select(_:)`'s list**, and each omission is deliberate:
    ///
    /// - **No `interaction.followFit()`.** A new *design* arrives fitted; an edit to the design
    ///   on screen keeps the zoom the user chose. Re-fitting on every parameter nudge would be
    ///   unusable, and this is the divergence between the two callers of one path that the
    ///   story names as the detail most likely to be missed.
    /// - **No new generation.** An edit is not a new selection; nothing downstream should treat
    ///   it as "start over".
    /// - **No `path` write.** Whatever the user is looking at — the script or the stage — stays.
    /// - **No `exporter.name` re-seed.** The name may be one the user typed.
    ///
    /// `reset()` is ADR-027's existing discard path: it cancels the consumer, bumps the run
    /// generation so buffered frames from the voided run cannot land, clears the display list
    /// and needle, and fires `onRunDiscarded`, which deletes the prepared file. The file is the
    /// part that actually goes stale — the interpreter took the program by value (ADR-026's
    /// eager preparation is why a stale file would otherwise be offered).
    private func programChanged() {
        selection?.provenance = nil
        runner.reset()
        persistWorkingProgram()
    }

    /// The revision of exactly the program this window holds; `nil` until it changes one. Not a
    /// "has edited" flag, which would let a superseded window put an older program back (3b).
    @ObservationIgnored private var heldRevision: SaveRevision?

    /// `onAppear` may fire twice; a second restore would replace the user's edits with the disk.
    @ObservationIgnored private var hasRestored = false

    /// Stamps the working program with a new revision and saves it — for every user-initiated
    /// change and nothing else. ADR-037 keeps the list; a rejected or unchanging edit and a
    /// restore are not on it.
    private func persistWorkingProgram() {
        let revision = autosave.mintRevision()
        heldRevision = revision
        autosave.save(editor.program, revision: revision)
    }

    /// Opens the saved working program, once per window (US-406) — from `onAppear`, not `init`,
    /// which `State(initialValue:)` evaluates on every view initialisation.
    ///
    /// A selection **without provenance** (ADR-038): the file records a program, not a sample.
    /// Its name is the title, and seeds the export only if the `LA` field can hold it. It holds
    /// no revision, so the window writes nothing until the user changes something.
    func restoreSavedProgram() {
        guard !hasRestored else { return }
        hasRestored = true
        switch autosave.restore() {
        case .nothingSaved:
            break
        case let .restored(program):
            editor.load(program)
            heldRevision = nil
            let title: LocalizedStringResource = program.name.isEmpty
                ? .programTitleUntitled : .programTitleNamed(program.name)
            selection = ProgramSelection(generation: nextGeneration, provenance: nil, title: title)
            nextGeneration += 1
            path = [.script] // Already so from `init`; kept so restore does not depend on it.
            palette.isPresented = false
            if case .success = DesignName.validating(program.name) {
                exporter.name = program.name
            }
            interaction.followFit()
        case let .refused(refusal):
            launchRefusal = refusal
        }
    }

    /// The window stopped being active: save what it holds, carrying the revision of the change
    /// that produced it, so the save is dropped if another window has changed the program since.
    func sceneDidLeaveActive() {
        guard let heldRevision else { return }
        autosave.save(editor.program, revision: heldRevision)
    }

    /// The user has read the launch refusal.
    func dismissLaunchRefusal() {
        launchRefusal = nil
    }

    /// Starts the selected design from the beginning, throwing away whatever the last run
    /// prepared.
    ///
    /// Round 1 of the cross-vendor review found Play Again leaving `exporter.state ==
    /// .ready(oldURL)` — that URL still holding the *previous* run — while the new run had
    /// already cleared the design. The discard lives on `RunViewModel.onRunDiscarded` rather
    /// than here, because round 2 pointed out that putting it in this method left the
    /// invariant as a convention: `runner.play(_:)` and `runner.reset()` are both reachable
    /// directly. This method now only checks that something is selected and runs the
    /// **working** program — `editor.program`, not the sample it was loaded from, which since
    /// US-405 the selection no longer carries.
    ///
    /// Since US-407 launch selects the blank program (ADR-039), so this guard no longer bites.
    func play() {
        guard selection != nil else { return }
        runner.play(editor.program)
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

    /// What the stage shows — its title, the sample it came from while it still is that
    /// sample, and which time it was chosen; set from `init` on (US-407). The program
    /// itself is `editor.program` (US-405, ADR-038).
    ///
    /// `private(set)` so every new selection goes through `select(_:)` and the
    /// generation can never be skipped — an assignment that bypassed it would
    /// reintroduce exactly the no-op this story exists to forbid. `restoreSavedProgram()` also
    /// mints one; `programChanged()` only clears `provenance`.
    private(set) var selection: ProgramSelection?

    /// The compact navigation stack's path.
    ///
    /// `var`, because `NavigationStack(path:)` writes back on Back and on the
    /// interactive swipe. A typed array rather than `NavigationPath` because a
    /// test can assert the whole value — `NavigationPath` is `Equatable` too, so
    /// the reason is readability of its *contents*, not equality, which an
    /// earlier version of this comment got wrong.
    ///
    /// Every writer — `init`, `select(_:)`, `restoreSavedProgram()` — assigns `[.script]`
    /// (US-407, ADR-039); the stage is pushed from the script by a `NavigationLink`. "A
    /// non-empty path implies a selection" holds from `init` on, since launch selects.
    var path: [StageDestination] = [] {
        didSet {
            // On compact the stage link stays tappable under a sheet that allows background
            // interaction (US-409). Pushing the stage must not carry the palette onto it — nor the
            // parameter editor's session (US-410).
            if path.last != .script {
                palette.isPresented = false
                editor.endParameterEdit()
            }
        }
    }

    /// The brick palette's presentation and its last insertion (US-409), beside `path` and
    /// `interaction` for ADR-023's reason: a flag held in the script list would close the palette
    /// on an iPad resize. Read and written through `AppModel+Palette.swift`.
    var palette = PaletteState()

    /// `@ObservationIgnored` on purpose: bumping the counter is bookkeeping, not
    /// state anyone renders, and the attribute keeps it out of the observation
    /// graph entirely.
    ///
    /// It is **not** what keeps `select(_:)` to a single notification, which an earlier version
    /// of this comment claimed. Observation is keypath-granular, so an un-ignored counter would
    /// notify only observers that had *read* it, and nothing reads it — it is `private`. And
    /// `select(_:)` mutates two observed properties anyway (`selection` and `path`), so the
    /// "exactly one observable mutation" discipline US-306 is held to is not a property this
    /// class has ever had. (In-loop review.)
    @ObservationIgnored private var nextGeneration = 0

    /// Selects `sample` and shows its script (US-407; the stage until then).
    ///
    /// **Loads a copy** into the editor and resets its history (US-405): the working program
    /// is a value, so editing it can never reach `SampleLibrary`, which is shared
    /// process-wide — asserted by `WorkingProgramTests` because a reference-typed model would
    /// make it false without a compiler error. Picking the sample again therefore throws the
    /// edits away, which is US-304's "start over" reaching the history too.
    ///
    /// Never a no-op, even for the sample already selected: the fresh generation
    /// makes the new value unequal to the old one, which is what lets a later
    /// consumer treat any selection as "start over" (US-306).
    ///
    /// The path is **assigned**, not appended to. Appending would stack a second
    /// script on the first, so Back would return to a script rather than to the
    /// list of samples.
    ///
    /// It writes `path` even when the split layout is showing, which ignores it.
    /// That is deliberate rather than a leak: it means a window resized down to
    /// compact opens on the design the user had selected, which is how UIKit's
    /// own split-view collapse behaves.
    /// It also **discards whatever the previous design left on the stage**, and it does
    /// so here rather than in a view. The view-side spellings — `.onChange(of:
    /// initial:)`, `.task(id:)` — re-fire when `RootView` rebuilds a navigation
    /// container after a horizontal size-class change (ADR-023), so on an iPad window
    /// resize they would wipe a design the user had just watched finish. The reset belongs
    /// with the selection's writers — `restoreSavedProgram()` skips it only because it runs
    /// once, before anything can play — and `programChanged()` is the other thing that voids a run.
    func select(_ sample: SampleProgram) {
        selection = ProgramSelection(
            generation: nextGeneration, provenance: sample.id, title: sample.displayName
        )
        editor.load(sample.program)
        persistWorkingProgram()
        nextGeneration += 1
        path = [.script]
        palette.isPresented = false
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
}
