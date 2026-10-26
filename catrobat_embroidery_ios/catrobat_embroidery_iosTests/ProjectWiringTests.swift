@testable import catrobat_embroidery_ios
import EditorCore
import EmbroideryEngine
import Foundation
import ProgramModel
import Samples
import StagePreview
import Testing

/// What each window saves, when, and what launch opens (project management slice 5; brief D3,
/// D6, D7), replacing US-406's `AutosaveWiringTests` now that every design is a project.
///
/// Driven through `AppModel`, because every claim is about wiring — an edit reaching the
/// store under the window's project, a lifecycle save carrying the right revision — and a test
/// of the library alone would pass with the wire cut. Two windows are two `AppModel`s sharing
/// one `ProjectLibrary`, which is what the `App` builds. A **relaunch** is a fresh `AppModel`
/// *and* a fresh `ProjectLibrary` over the same store and the same defaults: only what was
/// stored survives.
@MainActor
@Suite("Project wiring")
struct ProjectWiringTests {
    static let rosette = SampleLibrary[.octagonRosette]
    static let coil = SampleLibrary[.squareCoil]
    static let stored = ProjectID.fixed(1)

    /// One app: a store, the last-opened default and the library over them.
    struct App {
        let store: InMemoryProjectStore
        let remembered: LastOpenedProject
        let library: ProjectLibrary

        init(_ entries: [ProjectID: InMemoryProjectStore.Entry] = [:], lastOpened: ProjectID? = nil) {
            store = InMemoryProjectStore(entries)
            remembered = LastOpenedProject.disposable()
            remembered.id = lastOpened
            library = ProjectLibrary(store: store, lastOpened: remembered)
        }

        /// The same disk and defaults, a fresh process.
        init(relaunching app: App) {
            store = app.store
            remembered = app.remembered
            library = ProjectLibrary(store: store, lastOpened: remembered)
        }

        /// A window, launched the way `WindowRootView` launches one: built, then launched.
        func window(scene: ProjectID? = nil) -> AppModel {
            let model = AppModel(
                library: library,
                runner: RunViewModel(driver: InterpreterDriver(pacing: ImmediateRunPacing())),
                exporter: ExportViewModel(writer: RecordingDSTFileWriter())
            )
            model.launch(sceneID: scene)
            return model
        }
    }

    /// The bounded spin `ExportWiringTests` uses, for the reason it gives there.
    private static func settle(until condition: () -> Bool, turns: Int = 100_000) async {
        for _ in 0 ..< turns where !condition() {
            await Task.yield()
        }
    }

    /// Edits every program here accepts and that change it: no sample is called this.
    static let editQ = EditAction.renameProgram("M5 Q")
    static let editR = EditAction.renameProgram("M5 R")

    // MARK: Drafts (D3)

    @Test("with nothing stored, a window opens a draft that has no file and is registered")
    func launchOpensADraft() {
        let app = App()

        let model = app.window()

        var named = Program.blank
        named.name = "Design"
        #expect(model.editor.program == named)
        #expect(app.store.entries.isEmpty)
        #expect(app.library.holders(of: model.projectID) == [model.window])
        #expect(model.path == [.script])
    }

    /// Opening, running, exporting, navigating, backgrounding and closing are not changes.
    @Test("a sample draft writes nothing through running, exporting, navigating, leaving and closing")
    func aDraftWritesNothingUntilItChanges() async throws {
        let app = App()
        let model = app.window()

        model.select(Self.coil)
        model.play()
        await Self.settle(until: { model.runner.run.state == .finished(.programFinished) })
        try #require(model.exporter.state != .idle, "the premise: a file was prepared")
        model.path = [.script, .stage]
        model.path = [.script]
        model.sceneDidLeaveActive()
        model.close()

        #expect(app.store.saves.isEmpty)
        #expect(app.remembered.id == nil)
    }

    @Test("a draft's first change writes exactly its own file, and makes it the last opened")
    func theFirstChangeWritesTheDraft() {
        let app = App()
        let model = app.window()
        model.select(Self.coil)
        let draft = model.projectID

        model.editor.apply(Self.editQ)
        model.editor.apply(Self.editR)

        #expect(app.store.saves.map(\.id) == [draft, draft])
        #expect(app.store.program(draft) == model.editor.program)
        #expect(app.remembered.id == draft)
    }

    @Test("each sample pick is a new draft under a fresh ID")
    func eachPickIsANewDraft() {
        let app = App()
        let model = app.window()
        let launchDraft = model.projectID

        model.select(Self.coil)
        let first = model.projectID
        model.select(Self.coil)

        #expect(Set([launchDraft, first, model.projectID]).count == 3)
        #expect(app.library.holders(of: first).isEmpty)
        #expect(app.library.holders(of: model.projectID) == [model.window])
    }

    // MARK: Names (D4)

    @Test("a sample opens under its program's name, made unique among the projects")
    func aSampleIsNamedUniquely() {
        var named = Self.coil.program
        named.name = "Square Coil"
        let app = App([Self.stored: .program(named)])
        let model = app.window()

        model.select(Self.coil)

        var expected = Self.coil.program
        expected.name = "Square Coil 2"
        #expect(model.editor.program == expected)
    }

    @Test("another window's live draft reserves its name")
    func aLiveDraftReservesItsName() {
        let app = App()
        let windowA = app.window()
        let windowB = app.window()

        windowA.select(Self.rosette)
        windowB.select(Self.rosette)

        #expect(windowA.editor.program.name == Self.rosette.program.name)
        #expect(windowB.editor.program.name == "Octagon Roset 2")
    }

    /// Once the draft has a file its name is the file's, so a later rename frees the old one.
    @Test("a draft stops reserving its name once its first change has written it")
    func aWrittenDraftReservesNothing() throws {
        let app = App()
        let model = app.window()
        model.select(Self.coil)

        model.editor.apply(Self.editQ)
        model.editor.apply(Self.editR)

        #expect(try app.library.uniquedName(DesignName.validating("M5 Q").get()).value == "M5 Q")
    }

    // MARK: Launch (D6)

    @Test("launch opens the scene's project, makes it the last opened, and writes nothing")
    func launchOpensTheScenesProject() throws {
        let app = App([Self.stored: .program(Self.rosette.program)])

        let model = app.window(scene: Self.stored)

        #expect(model.projectID == Self.stored)
        #expect(model.editor.program == Self.rosette.program)
        #expect(model.nameDraft == Self.rosette.program.name, "the field shows the opened name")
        #expect(model.exporter.name == Self.rosette.program.name)
        #expect(try #require(model.selection).provenance == nil)
        #expect(app.remembered.id == Self.stored)
        #expect(app.library.holders(of: Self.stored) == [model.window])
        model.sceneDidLeaveActive()
        #expect(app.store.saves.isEmpty)
    }

    /// The resurrection case: a stale scene ID must not become the draft's ID, or the draft's
    /// first change would recreate the project the ID named.
    @Test("an unresolved scene ID is never reused for the draft")
    func anUnresolvedIDIsNeverReused() {
        let app = App()

        let model = app.window(scene: Self.stored)
        model.editor.apply(Self.editQ)

        #expect(model.projectID != Self.stored)
        #expect(app.store.entries[Self.stored] == nil)
    }

    @Test("a refused project is alerted for under its ID, and the draft never touches its file")
    func aRefusedProjectIsAlertedAndKept() throws {
        let app = App([Self.stored: .refused(.unsupportedVersion(2), name: "Future")])

        let model = app.window(scene: Self.stored)
        model.editor.apply(Self.editQ)
        model.sceneDidLeaveActive()

        #expect(try #require(model.launchRefusal).reason == .document(.unsupportedVersion(2)))
        #expect(model.projectID != Self.stored)
        #expect(app.store.entries[Self.stored] == .refused(.unsupportedVersion(2), name: "Future"))
    }

    @Test("an edited project reopens after a relaunch, with nothing to undo")
    func anEditSurvivesARelaunch() {
        let app = App()
        let model = app.window()
        model.select(Self.coil)
        model.editor.apply(Self.editQ)
        let edited = model.editor.program

        let relaunched = App(relaunching: app).window()

        #expect(relaunched.editor.program == edited)
        #expect(relaunched.projectID == model.projectID)
        #expect(!relaunched.editor.canUndo)
    }

    @Test("launching a window twice does not replace its program")
    func launchingTwiceKeepsTheProgram() {
        let app = App([Self.stored: .program(Self.rosette.program)])
        app.store.failingSaves = [Self.stored]
        let model = app.window(scene: Self.stored)
        model.editor.apply(Self.editQ)
        let edited = model.editor.program

        model.launch(sceneID: Self.stored)

        #expect(model.editor.program == edited)
    }

    // MARK: Several windows (D7)

    /// ADR-037's 3b, per project: a per-window "has edited" flag would let A's stale Q land
    /// over B's newer R.
    @Test("with two windows on one project, the newer edit survives the older window leaving")
    func theNewerEditSurvives() {
        let app = App([Self.stored: .program(Self.rosette.program)])
        let windowA = app.window(scene: Self.stored)
        let windowB = app.window(scene: Self.stored)

        windowA.editor.apply(Self.editQ)
        windowB.editor.apply(Self.editR)
        let programR = windowB.editor.program
        windowA.sceneDidLeaveActive()

        #expect(app.store.program(Self.stored) == programR)
    }

    @Test("a window that changed nothing does not overwrite another window's edit")
    func anUnchangedWindowDoesNotOverwrite() {
        let app = App([Self.stored: .program(Self.rosette.program)])
        let windowA = app.window(scene: Self.stored)
        let windowB = app.window(scene: Self.stored)

        windowA.editor.apply(Self.editQ)
        windowB.sceneDidLeaveActive()

        #expect(app.store.saves.map(\.program) == [windowA.editor.program])
    }

    @Test("a failing save shows in the window holding that project, and not in another")
    func aFailureShowsOnlyWhereItHappened() {
        let app = App([Self.stored: .program(Self.rosette.program)])
        app.store.failingSaves = [Self.stored]
        let failing = app.window(scene: Self.stored)
        let other = app.window()

        failing.editor.apply(Self.editQ)
        other.select(Self.coil)
        other.editor.apply(Self.editR)

        #expect(failing.saveFailure == .saveFailed)
        #expect(other.saveFailure == nil)
    }

    @Test("closing a window releases its project")
    func closingReleasesTheProject() {
        let app = App([Self.stored: .program(Self.rosette.program)])
        let model = app.window(scene: Self.stored)

        model.close()

        #expect(app.library.holders(of: Self.stored).isEmpty)
    }
}
