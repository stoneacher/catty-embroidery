@testable import catrobat_embroidery_ios
import EditorCore
import EmbroideryEngine
import Foundation
import ProgramModel
import Projects
import Samples
import Testing

/// Renaming (project management slice 9; brief D8): the list's sheet and the stage's field
/// each hold the typed text in a transient buffer, so an invalid name never reaches the
/// program, the list, the history or the disk. The sheet renames the open project by an edit
/// (undoable, through the pipeline) and a closed one through the catalog.
///
/// Driven through `AppModel` for the reason `ProjectWiringTests` gives.
@MainActor
@Suite("Project rename")
struct ProjectRenameTests {
    typealias App = ProjectWiringTests.App
    static let rosette = SampleLibrary[.octagonRosette].program
    static let coil = SampleLibrary[.squareCoil].program
    static let first = ProjectID.fixed(1)
    static let second = ProjectID.fixed(2)

    static func twoProjects() -> App {
        App([first: .program(rosette), second: .program(coil)], lastOpened: first)
    }

    static func row(_ id: ProjectID, in app: App) throws -> ProjectRow {
        guard case let .rows(rows) = ProjectListPresentation.content(
            files: app.library.files, openID: .fixed(99), showsSelection: false
        ) else {
            throw RowMissing()
        }
        return try #require(rows.first { $0.id == id })
    }

    struct RowMissing: Error {}

    // MARK: The sheet's buffer

    @Test("beginning a rename holds the row's name and writes nothing")
    func beginning() throws {
        let app = Self.twoProjects()
        let model = app.window()

        try model.beginRename(of: Self.row(Self.second, in: app))

        #expect(model.listState.rename?.id == Self.second)
        #expect(model.listState.rename?.text == Self.coil.name)
        #expect(app.store.saves.isEmpty)
    }

    @Test(
        "Save is allowed only for a valid name",
        arguments: [("Flower", true), ("", false), ("   ", false), ("Sixteen chars ok", false), ("Über", false)]
    )
    func saveNeedsAValidName(text: String, canSave: Bool) {
        var session = RenameSession(id: .fixed(1), originalName: "Old", text: "Old")
        session.text = text

        #expect(session.canSave == canSave)
    }

    @Test("an invalid name is not saved: the sheet stays with what was typed, and nothing changes")
    func anInvalidNameStays() throws {
        let app = Self.twoProjects()
        let model = app.window()
        try model.beginRename(of: Self.row(Self.second, in: app))
        model.listState.rename?.text = "Far too long a name"

        #expect(!model.commitRename())

        #expect(model.listState.rename?.text == "Far too long a name")
        #expect(app.store.saves.isEmpty)
        #expect(app.store.program(Self.second) == Self.coil)
    }

    @Test("cancelling writes nothing")
    func cancelling() throws {
        let app = Self.twoProjects()
        let model = app.window()
        try model.beginRename(of: Self.row(Self.second, in: app))
        model.listState.rename?.text = "Renamed"

        model.cancelRename()

        #expect(model.listState.rename == nil)
        #expect(app.store.saves.isEmpty)
    }

    // MARK: Routing (D8)

    @Test("a closed project is renamed through the catalog, trimmed, and the window is untouched")
    func renamingAClosedProject() throws {
        let app = Self.twoProjects()
        let model = app.window()
        try model.beginRename(of: Self.row(Self.second, in: app))
        model.listState.rename?.text = "  Coil  "

        #expect(model.commitRename())

        #expect(app.store.program(Self.second)?.name == "Coil")
        #expect(model.listState.rename == nil)
        #expect(model.projectID == Self.first)
        #expect(model.editor.program == Self.rosette)
        #expect(!model.editor.canUndo)
    }

    @Test("the open project is renamed by an edit: undoable, saved, and the field follows")
    func renamingTheOpenProject() throws {
        let app = Self.twoProjects()
        let model = app.window()
        try model.beginRename(of: Self.row(Self.first, in: app))
        model.listState.rename?.text = "Rosette"

        #expect(model.commitRename())

        #expect(model.editor.program.name == "Rosette")
        #expect(model.editor.canUndo)
        #expect(model.nameDraft == "Rosette")
        #expect(app.store.saves.map(\.id) == [Self.first])
        #expect(model.listState.rename == nil)
    }

    @Test("an unchanged name writes nothing")
    func unchangedName() throws {
        let app = Self.twoProjects()
        let model = app.window()
        try model.beginRename(of: Self.row(Self.second, in: app))

        #expect(model.commitRename())

        #expect(app.store.saves.isEmpty)
        #expect(model.listState.rename == nil)
    }

    @Test("a closed project another window holds is not renamed, and the user is told why")
    func aHeldProjectIsNotRenamed() throws {
        let app = Self.twoProjects()
        // Kept alive to the end: the registry holds windows weakly.
        let other = app.window(scene: Self.second)
        // On `first` by name: opening `second` above made it the last opened.
        let model = app.window(scene: Self.first)
        try model.beginRename(of: Self.row(Self.second, in: app))
        model.listState.rename?.text = "Coil"

        model.commitRename()

        #expect(app.store.program(Self.second) == Self.coil)
        #expect(model.listState.notice == .heldElsewhere(name: Self.coil.name))
        #expect(model.listState.rename == nil)
        #expect(other.editor.program == Self.coil)
    }

    @Test("a rename that cannot be written says so and changes nothing")
    func aFailedRename() throws {
        let app = Self.twoProjects()
        let model = app.window()
        app.store.failingSaves = [Self.second]
        try model.beginRename(of: Self.row(Self.second, in: app))
        model.listState.rename?.text = "Coil"

        model.commitRename()

        #expect(model.listState.notice == .renameFailed(name: Self.coil.name))
        #expect(app.store.program(Self.second) == Self.coil)
    }

    // MARK: The stage's field (D8's transient buffer)

    @Test("typing in the stage's field changes nothing until it is committed")
    func typingCommitsNothing() {
        let app = Self.twoProjects()
        let model = app.window()

        model.nameDraft = "Rosett"
        model.nameDraft = "Rosette"

        #expect(model.editor.program == Self.rosette)
        #expect(app.store.saves.isEmpty)
    }

    @Test("submitting an invalid name keeps what was typed, and changes nothing")
    func anInvalidSubmitKeepsTheText() {
        let app = Self.twoProjects()
        let model = app.window()
        model.nameDraft = "Far too long a name"

        #expect(!model.submitName())

        #expect(model.nameDraft == "Far too long a name")
        #expect(model.editor.program == Self.rosette)
        #expect(app.store.saves.isEmpty)
    }

    @Test("submitting a valid name renames the design")
    func aValidSubmitRenames() {
        let app = Self.twoProjects()
        let model = app.window()
        model.nameDraft = " Rosette "

        #expect(model.submitName())

        #expect(model.editor.program.name == "Rosette")
        #expect(model.nameDraft == "Rosette")
    }

    @Test("losing focus on an invalid name returns the field to the committed name")
    func focusLossReverts() {
        let app = Self.twoProjects()
        let model = app.window()
        model.nameDraft = "Far too long a name"

        model.nameFieldLostFocus()

        #expect(model.nameDraft == Self.rosette.name)
        #expect(model.editor.program == Self.rosette)
    }

    @Test("losing focus on a valid name commits it")
    func focusLossCommits() {
        let app = Self.twoProjects()
        let model = app.window()
        model.nameDraft = "Rosette"

        model.nameFieldLostFocus()

        #expect(model.editor.program.name == "Rosette")
    }
}
