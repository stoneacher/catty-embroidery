@testable import catrobat_embroidery_ios
import EditorCore
import Foundation
import ProgramModel
import Samples
import StagePreview
import Testing

/// US-406's test-first plan at the app layer: what each window saves, when, and what launch
/// does with what it finds (ADR-037, multi-window half).
///
/// Driven through `AppModel`, because every claim is about wiring — an edit reaching the
/// store, a lifecycle save carrying the right revision — and a test of the coordinator alone
/// would pass with the wire cut. Two windows are two `AppModel`s sharing one `ProgramAutosave`,
/// which is exactly what the `App` builds. A **relaunch** is a fresh `AppModel` *and* a fresh
/// `ProgramAutosave` over the same store: nothing in memory survives, only what was stored.
@MainActor
@Suite("Autosave wiring")
struct AutosaveWiringTests {
    private static let rosette = SampleLibrary[.octagonRosette]
    private static let coil = SampleLibrary[.squareCoil]

    /// A window, launched the way `WindowRootView` launches one: built, then restored.
    private static func window(_ autosave: ProgramAutosave) -> AppModel {
        let model = AppModel(
            autosave: autosave,
            runner: RunViewModel(driver: InterpreterDriver(pacing: ImmediateRunPacing())),
            exporter: ExportViewModel(writer: RecordingDSTFileWriter())
        )
        model.restoreSavedProgram()
        return model
    }

    private static func relaunch(_ store: some ProgramStoring) -> AppModel {
        window(ProgramAutosave(store: store))
    }

    /// Edits every program in this suite accepts and that change it: no sample is called this.
    private static let editQ = EditAction.renameProgram("US-406 Q")
    private static let editR = EditAction.renameProgram("US-406 R")

    // MARK: 1 — round trip

    @Test("an edited program survives a relaunch as a whole value")
    func anEditedProgramSurvivesARelaunch() {
        let store = InMemoryProgramStore()
        let model = Self.window(ProgramAutosave(store: store))
        model.select(Self.coil)
        model.editor.apply(Self.editQ)
        let edited = model.editor.program

        let relaunched = Self.relaunch(store)

        #expect(relaunched.editor.program == edited)
    }

    // MARK: 1b — a window that changed nothing

    /// The test that fails an edit-only rule's naive form: B's unchanged program must not be
    /// written over A's edit when B leaves the foreground.
    @Test("a window that changed nothing does not overwrite another window's edit")
    func anUnchangedWindowDoesNotOverwriteAnEdit() {
        let store = InMemoryProgramStore(stored: Self.rosette.program)
        let autosave = ProgramAutosave(store: store)
        let windowA = Self.window(autosave)
        let windowB = Self.window(autosave)

        windowA.editor.apply(Self.editQ)
        let programQ = windowA.editor.program
        windowB.sceneDidLeaveActive()

        #expect(store.stored == programQ)
        #expect(store.saves == [programQ])
    }

    // MARK: 2 — what an edit writes

    @Test("an applied edit saves exactly once")
    func anAppliedEditSavesOnce() {
        let store = InMemoryProgramStore()
        let model = Self.window(ProgramAutosave(store: store))
        model.select(Self.coil)
        let savesBefore = store.saves.count

        model.editor.apply(Self.editQ)

        #expect(store.saves.count == savesBefore + 1)
        #expect(store.saves.last == model.editor.program)
    }

    /// Needs mutation proof: a do-nothing stub saves nothing either.
    @Test("a rejected edit and an edit that changes nothing save nothing")
    func aRejectedOrUnchangingEditSavesNothing() {
        let store = InMemoryProgramStore()
        let model = Self.window(ProgramAutosave(store: store))
        model.editor.apply(Self.editQ)
        let savesBefore = store.saves.count

        let rejected = model.editor.apply(.insert(.loopEnd, at: BrickAddress(brickIndex: 0)))
        model.editor.apply(Self.editQ)

        #expect(rejected == .rejected(.cannotInsertLoopEnd))
        #expect(store.saves.count == savesBefore)
    }

    // MARK: 3 — leaving the foreground

    @Test("leaving the foreground after an edit saves the edited program again")
    func leavingAfterAnEditSaves() {
        let store = InMemoryProgramStore()
        let model = Self.window(ProgramAutosave(store: store))
        model.editor.apply(Self.editQ)

        model.sceneDidLeaveActive()

        #expect(store.saves == [model.editor.program, model.editor.program])
    }

    @Test("picking a sample saves it, and leaving the foreground saves it again")
    func pickingASampleSaves() {
        let store = InMemoryProgramStore()
        let model = Self.window(ProgramAutosave(store: store))

        model.select(Self.coil)
        model.sceneDidLeaveActive()

        #expect(store.saves == [Self.coil.program, Self.coil.program])
    }

    /// Needs mutation proof: a do-nothing stub writes nothing either.
    @Test("a window that only restored does not write when it leaves the foreground")
    func aRestoredWindowDoesNotWrite() {
        let store = InMemoryProgramStore(stored: Self.rosette.program)
        let model = Self.window(ProgramAutosave(store: store))

        model.sceneDidLeaveActive()

        #expect(store.saves.isEmpty)
    }

    /// Test-plan item 3b. A per-window "has edited" flag fails this: A has edited, so its
    /// lifecycle save would put the stale Q over B's newer R.
    @Test("with two edited windows, the newer edit survives the older window leaving")
    func theNewerEditSurvives() {
        let store = InMemoryProgramStore(stored: Self.rosette.program)
        let autosave = ProgramAutosave(store: store)
        let windowA = Self.window(autosave)
        let windowB = Self.window(autosave)

        windowA.editor.apply(Self.editQ)
        let programQ = windowA.editor.program
        windowB.editor.apply(Self.editR)
        let programR = windowB.editor.program
        windowA.sceneDidLeaveActive()

        #expect(store.stored == programR)
        #expect(store.saves == [programQ, programR])
    }

    /// Test-plan item 3c. The one that fails a rule phrased as "only an edit writes": a sample
    /// pick is a replacement, not an `EditAction`.
    @Test("a picked sample survives a relaunch without a single edit")
    func aPickedSampleSurvivesARelaunch() {
        let store = InMemoryProgramStore(stored: Self.rosette.program)
        let model = Self.window(ProgramAutosave(store: store))

        model.select(Self.coil)
        model.sceneDidLeaveActive()
        let relaunched = Self.relaunch(store)

        #expect(relaunched.editor.program == Self.coil.program)
    }

    // MARK: 3d, 4 — launch

    /// Test-plan item 3d. The "writes nothing back" half needs mutation proof.
    @Test("restoring a saved program opens it on the stage and writes nothing back")
    func restoringOpensTheProgramAndWritesNothing() {
        let store = InMemoryProgramStore(stored: Self.coil.program)

        let model = Self.relaunch(store)

        #expect(model.editor.program == Self.coil.program)
        #expect(model.path == [.stage])
        #expect(model.selection != nil)
        #expect(model.selection?.provenance == nil)
        #expect(model.launchRefusal == nil)
        #expect(store.saves.isEmpty)
    }

    /// Test-plan item 4. Needs mutation proof: it is the state a do-nothing stub leaves.
    @Test("with nothing saved, launch is the blank program with no error")
    func nothingSavedIsAFirstLaunch() {
        let store = InMemoryProgramStore()

        let model = Self.relaunch(store)

        #expect(model.editor.program == .blank)
        #expect(model.selection == nil)
        #expect(model.path.isEmpty)
        #expect(model.launchRefusal == nil)
        #expect(model.saveFailure == nil)
        #expect(store.saves.isEmpty)
    }

    /// `onAppear` can fire more than once per window; a second restore would replace the
    /// user's edits with the copy on disk.
    @Test("restoring again does not replace the window's program")
    func restoringIsOncePerWindow() {
        let store = InMemoryProgramStore(stored: Self.coil.program)
        let model = Self.relaunch(store)
        store.failsSaves = true
        model.editor.apply(Self.editQ)
        let edited = model.editor.program

        model.restoreSavedProgram()

        #expect(model.editor.program == edited)
        #expect(store.loadCount == 1)
    }

    @Test("a restored program is titled with its own name, and that name seeds the export")
    func aRestoredProgramIsTitledWithItsName() throws {
        let store = InMemoryProgramStore(stored: Self.coil.program)

        let model = Self.relaunch(store)

        let title = try #require(model.selection?.title)
        #expect(String(localized: title) == "Square Coil")
        #expect(model.exporter.name == "Square Coil")
    }

    @Test("a restored program with no name is Untitled, and seeds no export name")
    func aRestoredProgramWithNoNameIsUntitled() throws {
        var unnamed = Self.coil.program
        unnamed.name = ""
        let store = InMemoryProgramStore(stored: unnamed)

        let model = Self.relaunch(store)

        let title = try #require(model.selection?.title)
        #expect(String(localized: title) == "Untitled Design")
        #expect(model.exporter.name.isEmpty)
    }

    /// A name the `LA` field cannot hold is still the title, but must not open the stage
    /// already showing a validation error the user did not cause.
    @Test("a restored name the export cannot use is the title but not the export name")
    func anUnexportableNameIsNotSeeded() throws {
        var longName = Self.coil.program
        longName.name = "A name much longer than fifteen"
        let store = InMemoryProgramStore(stored: longName)

        let model = Self.relaunch(store)

        let title = try #require(model.selection?.title)
        #expect(String(localized: title) == "A name much longer than fifteen")
        #expect(model.exporter.name.isEmpty)
    }

    // MARK: 5, 6, 6b — a refused file

    /// Preservation is asserted on the **original bytes at the preserved location**, and only
    /// after an edit and a lifecycle save have both had their chance to write — "a file exists
    /// at the working path" would also pass a load that deleted the document and an autosave
    /// that recreated the path.
    @Test("a refused file opens a blank program, says why, and its bytes survive later saves",
          arguments: RefusedFixture.allCases)
    func aRefusedFileIsPreserved(_ refused: RefusedFixture) throws {
        try inDisposableDirectory { directory in
            let disk = DocumentsProgramStore(directory: directory)
            let original = try refused.bytes
            try original.write(to: disk.workingURL)

            let model = Self.relaunch(disk)

            #expect(model.editor.program == .blank)
            #expect(model.selection == nil)
            let refusal = try #require(model.launchRefusal)
            #expect(refused.matches(refusal.reason), "reason was \(refusal.reason)")
            #expect(refusal.preserved)

            model.editor.apply(Self.editQ)
            model.sceneDidLeaveActive()

            #expect(try setAsideFiles(in: directory) == [original])
            #expect(try disk.load() == model.editor.program)
        }
    }

    /// Test-plan item 11. The bytes half needs mutation proof — a store that writes nothing
    /// leaves them intact too — and the state half is what a stub cannot fake.
    @Test("if the refused file cannot be set aside, the blank program never overwrites it")
    func anUnpreservedFileIsNeverOverwritten() throws {
        try inDisposableDirectory { directory in
            let disk = DocumentsProgramStore(directory: directory)
            try RefusedDocument.corrupt.write(to: disk.workingURL)

            let model = Self.relaunch(SetAsideFailingStore(wrapping: disk))
            model.editor.apply(Self.editQ)
            model.sceneDidLeaveActive()

            #expect(model.launchRefusal == ProgramRefusal(reason: .document(.corrupt), preserved: false))
            #expect(model.saveFailure == .unpreservedDocument)
            #expect(try Data(contentsOf: disk.workingURL) == RefusedDocument.corrupt)
        }
    }

    @Test("dismissing the launch refusal clears it")
    func dismissingTheRefusalClearsIt() throws {
        let store = InMemoryProgramStore()
        store.loadError = .document(.corrupt)
        let model = Self.relaunch(store)
        try #require(model.launchRefusal != nil)

        model.dismissLaunchRefusal()

        #expect(model.launchRefusal == nil)
    }

    // MARK: 7 — a failing save

    @Test("a failing save reaches the window rather than being swallowed")
    func aFailingSaveReachesTheWindow() {
        let store = InMemoryProgramStore()
        store.failsSaves = true
        let model = Self.window(ProgramAutosave(store: store))

        model.editor.apply(Self.editQ)

        #expect(model.saveFailure == .saveFailed)
    }

    // MARK: 8 — history is not persisted

    /// The `canUndo` half cannot fail by construction — a relaunch builds a fresh editor — and
    /// is a regression pin, not a mutation-proved guard: ADR-006 decided the history is not
    /// persisted, and this is what stops someone "improving" that without deciding to.
    @Test("after a relaunch the program is the saved one and there is nothing to undo")
    func aRelaunchStartsWithNoHistory() {
        let store = InMemoryProgramStore()
        let model = Self.window(ProgramAutosave(store: store))
        model.select(Self.coil)
        model.editor.apply(Self.editQ)
        model.editor.apply(Self.editR)
        #expect(model.editor.undoStack.canUndo, "the premise: there was history to lose")

        let relaunched = Self.relaunch(store)

        #expect(relaunched.editor.program == model.editor.program)
        #expect(!relaunched.editor.undoStack.canUndo)
    }
}

/// The three refused-file fixtures test-plan items 5, 6 and 6b share.
enum RefusedFixture: CaseIterable, CustomTestStringConvertible {
    case futureVersion, corrupt, unbalanced

    var bytes: Data {
        get throws {
            switch self {
            case .futureVersion: try RefusedDocument.futureVersion
            case .corrupt: RefusedDocument.corrupt
            case .unbalanced: try RefusedDocument.unbalanced
            }
        }
    }

    func matches(_ reason: ProgramLoadError) -> Bool {
        switch (self, reason) {
        case (.futureVersion, .document(.unsupportedVersion(2))),
             (.corrupt, .document(.corrupt)),
             (.unbalanced, .document(.unbalancedScript)):
            true
        default:
            false
        }
    }

    var testDescription: String {
        "\(self)"
    }
}
