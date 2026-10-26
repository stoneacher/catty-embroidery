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

    /// Every project file's guard, shared with every other window (project management
    /// slice 5; ADR-037 per project).
    let library: ProjectLibrary

    /// This window, as the library's registry knows it (brief D7).
    let window = WindowToken()

    /// The project this window holds: an existing one, or a draft with no file yet (brief D3).
    /// Observed, because the scene stores it.
    private(set) var projectID: ProjectID

    /// Whether `projectID` has a file this window opened or wrote. A draft has none until its
    /// first change.
    @ObservationIgnored private var hasFile = false

    /// A project found at launch and not opened, until the user has been told.
    private(set) var launchRefusal: ProgramRefusal?

    /// What the stage's name field holds (brief D8's transient buffer): raw, possibly invalid,
    /// reaching the program only through `commitName()` as a valid rename. Every change and
    /// every load set it back to `program.name`.
    var nameDraft = ""

    /// Why this window's project is not being saved, or `nil` while it is.
    var saveFailure: ProjectSaveFailure? {
        library.failure(for: projectID)
    }

    /// The rest are injectable so tests can supply immediate pacing and a recording writer;
    /// the defaults are what the app runs with. `library` has no default: it is shared across
    /// windows, so only their owner can supply it, and a default would be silent non-saving.
    ///
    /// The window starts on a draft ID, unregistered: `init` must stay free of side effects
    /// (see `WindowRootView`), so `launch(sceneID:)` decides what the window really holds.
    init(
        library: ProjectLibrary,
        runner: RunViewModel = RunViewModel(),
        exporter: ExportViewModel = ExportViewModel(),
        editor: EditorViewModel = EditorViewModel()
    ) {
        self.runner = runner
        self.exporter = exporter
        self.editor = editor
        self.library = library
        projectID = library.makeDraftID()

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
        editor.onProgramChanged = { [weak self] before, after in
            self?.programChanged(from: before, to: after)
        }

        // Launch selects the blank program, opening on its script (US-407) — see `.launch`.
        selection = .launch(generation: nextGeneration)
        nextGeneration += 1
        path = [.script]
    }

    /// What an edit, an undo or a redo (US-408) does to the window (ADR-038) — one handler, so
    /// undoing to P after running Q cannot leave Q's `.dst` offered.
    ///
    /// **A change that differs only in the name keeps the run** (project management, brief D8,
    /// amending ADR-038/045): the stitches are the same, so only the export is re-prepared,
    /// under the new name. Judged on the values reaching this chokepoint, so a rename's undo
    /// and redo are judged the same way, and a run a content change already voided stays void:
    /// there is nothing finished to re-prepare. Every change is saved.
    ///
    /// Every other change: **`runner.reset()` and nothing else from `select(_:)`'s list**, and
    /// each omission is deliberate:
    ///
    /// - **No `interaction.followFit()`.** A new *design* arrives fitted; an edit to the design
    ///   on screen keeps the zoom the user chose. Re-fitting on every parameter nudge would be
    ///   unusable, and this is the divergence between the two callers of one path that the
    ///   story names as the detail most likely to be missed.
    /// - **No new generation.** An edit is not a new selection; nothing downstream should treat
    ///   it as "start over".
    /// - **No `path` write.** Whatever the user is looking at — the script or the stage — stays.
    /// - **No zoom, generation or path change** applies to a rename as much as to any edit.
    ///
    /// `reset()` is ADR-027's existing discard path: it cancels the consumer, bumps the run
    /// generation so buffered frames from the voided run cannot land, clears the display list
    /// and needle, and fires `onRunDiscarded`, which deletes the prepared file. The file is the
    /// part that actually goes stale — the interpreter took the program by value (ADR-026's
    /// eager preparation is why a stale file would otherwise be offered).
    private func programChanged(from before: Program, to after: Program) {
        selection?.provenance = nil
        if after.differsOnlyInName(from: before) {
            syncName()
            // Only a finished run has an export model: `begin()` clears it and only a
            // termination sets it, so a rename mid-run prepares nothing until the run ends.
            if let exportModel = runner.run.exportModel {
                exporter.prepare(exportModel: exportModel)
            }
        } else {
            runner.reset()
            syncName()
        }
        persistWorkingProgram()
    }

    /// The revision of exactly the program this window holds; `nil` until it changes one. Not a
    /// "has edited" flag, which would let a superseded window put an older program back (3b).
    @ObservationIgnored private var heldRevision: SaveRevision?

    /// `onAppear` may fire twice; a second launch would replace the user's edits with the disk.
    @ObservationIgnored private var hasLaunched = false

    /// Stamps the working program with a new revision and saves it to this window's project —
    /// for every user-initiated change and nothing else. ADR-037 keeps the list; a rejected or
    /// unchanging edit, an opening and a sample pick are not on it (brief D3). A draft's first
    /// written save gives it a file: it stops reserving its name and becomes the last opened.
    private func persistWorkingProgram() {
        let revision = library.mintRevision()
        heldRevision = revision
        guard library.save(editor.program, to: projectID, revision: revision) == .written, !hasFile else {
            return
        }
        hasFile = true
        library.register(window, owner: self, holding: projectID, draftName: nil)
        library.markOpened(projectID)
    }

    /// Opens what this window holds, once per window — from `onAppear`, not `init`, which
    /// `State(initialValue:)` evaluates on every view initialisation. Brief D6: the scene's
    /// project, else the last opened, else a draft under a **fresh** ID, so a stale ID can
    /// never become a draft that recreates what it named. The first refused candidate is
    /// alerted for; its file stays where it is.
    ///
    /// An opened project is a selection **without provenance** (ADR-038): the file records a
    /// program, not a sample. Its name is the title, and seeds the export only if the `LA`
    /// field can hold it. It holds no revision, so the window writes nothing until the user
    /// changes something.
    func launch(sceneID: ProjectID?) {
        guard !hasLaunched else { return }
        hasLaunched = true
        let resolution = library.resolveLaunch(sceneID: sceneID)
        launchRefusal = resolution.refusals.first.map { ProgramRefusal(reason: $0.reason) }
        guard let opened = resolution.opened else {
            var blank = Program.blank
            blank.name = Self.defaultName.value
            startDraft(from: blank)
            selection = ProgramSelection(
                generation: nextGeneration, provenance: nil, title: .programTitleNamed(editor.program.name)
            )
            nextGeneration += 1
            return
        }
        projectID = opened.id
        hasFile = true
        library.register(window, owner: self, holding: projectID, draftName: nil)
        editor.load(opened.program)
        heldRevision = nil
        let title: LocalizedStringResource = opened.program.name.isEmpty
            ? .programTitleUntitled : .programTitleNamed(opened.program.name)
        selection = ProgramSelection(generation: nextGeneration, provenance: nil, title: title)
        nextGeneration += 1
        path = [.script] // Already so from `init`; kept so launch does not depend on it.
        palette.isPresented = false
        syncName()
        interaction.followFit()
    }

    /// The window stopped being active: save what it holds, carrying the revision of the change
    /// that produced it, so the save is dropped if another window has changed the program since.
    func sceneDidLeaveActive() {
        guard let heldRevision else { return }
        library.save(editor.program, to: projectID, revision: heldRevision)
    }

    /// The window is going away: it no longer holds its project (brief D7).
    func close() {
        library.unregister(window, from: projectID)
    }

    /// The user has read the launch refusal.
    func dismissLaunchRefusal() {
        launchRefusal = nil
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
    /// reintroduce exactly the no-op this story exists to forbid. `launch(sceneID:)` also
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
    /// Every writer — `init`, `select(_:)`, `launch(sceneID:)` — assigns `[.script]`
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
    /// with the selection's writers — `launch(sceneID:)` skips it only because it runs
    /// once, before anything can play — and `programChanged()` is the other thing that voids a run.
    func select(_ sample: SampleProgram) {
        selection = ProgramSelection(
            generation: nextGeneration, provenance: sample.id, title: sample.displayName
        )
        startDraft(from: sample.program)
        nextGeneration += 1
        path = [.script]
        palette.isPresented = false
        // `reset()` discards the run, which fires `onRunDiscarded` and takes the previous
        // design's file with it. Leaving the file would offer a share button that sends the
        // *last* design — the staleness ADR-023 exists to prevent, one layer up.
        runner.reset()
        // A new design arrives fitted. Inheriting the previous design's 4× zoom would show a
        // corner of something the user has not seen whole yet — and the zoom was chosen
        // against a fit that no longer applies. Here rather than in an `.onChange`, for the
        // reason the run's reset is here: the view-side spellings re-fire on the ADR-023
        // container rebuild.
        interaction.followFit()
    }

    /// A sample opens as a **draft** (brief D3): a fresh ID with no file, which the first
    /// change writes. Named after its program, made unique among every name the user can see
    /// (D4), and registered so another window's generated names avoid it.
    /// The registration replaces whatever the window held before, so the old project needs no
    /// separate unregister.
    private func startDraft(from program: Program) {
        projectID = library.makeDraftID()
        hasFile = false
        heldRevision = nil
        var named = program
        if case let .success(name) = DesignName.validating(program.name) {
            named.name = library.uniquedName(name).value
        }
        editor.load(named)
        library.register(window, owner: self, holding: projectID, draftName: named.name)
        syncName()
    }
}
