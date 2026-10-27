@testable import catrobat_embroidery_ios
import EditorCore
import Foundation
import ProgramModel
import Projects
import Samples
import StagePreview
import Testing

/// The list's verbs (project management slice 8; brief D3, D4, D7, D9): "+" opens a blank
/// draft, Duplicate writes a copy at once and selects nothing new, Delete happens only after
/// confirmation, exactly once, and a failed or refused delete changes nothing.
///
/// Driven through `AppModel` for the reason `ProjectWiringTests` gives.
@MainActor
@Suite("Project list actions")
struct ProjectListActionsTests {
    typealias App = ProjectWiringTests.App
    static let rosette = SampleLibrary[.octagonRosette].program
    static let coil = SampleLibrary[.squareCoil].program
    static let first = ProjectID.fixed(1)
    static let second = ProjectID.fixed(2)

    static func named(_ name: String, _ program: Program = rosette) -> Program {
        var renamed = program
        renamed.name = name
        return renamed
    }

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

    // MARK: "+" (D3)

    @Test("\"+\" opens a blank draft, uniquely named, on its script, and writes nothing")
    func newDesign() async {
        let app = App([Self.first: .program(Self.named("Design"))], lastOpened: Self.first)
        let model = app.window()
        model.path = []
        let before = model.selection?.generation
        model.play()
        for _ in 0 ..< 100_000 where model.runner.run.display.isEmpty {
            await Task.yield()
        }

        model.newDesign()

        #expect(model.projectID != Self.first)
        #expect(model.editor.program == Self.named("Design 2", .blank))
        #expect(!model.editor.canUndo)
        #expect(model.path == [.script])
        #expect(model.selection?.generation != before)
        #expect(model.selection?.provenance == nil)
        #expect(model.runner.run.display.isEmpty)
        #expect(app.store.saves.isEmpty)
        #expect(app.library.holders(of: Self.first).isEmpty)
        #expect(app.library.holders(of: model.projectID) == [model.window])
    }

    @Test("\"+\" retries a failed save first, and stays if it fails again")
    func newDesignKeepsAnUnsavedProject() {
        let app = Self.twoProjects()
        let model = app.window()
        app.store.failingSaves = [Self.first]
        model.editor.apply(.renameProgram("Unsaved"))

        model.newDesign()

        #expect(model.projectID == Self.first)
        #expect(model.editor.program.name == "Unsaved")
    }

    // MARK: Duplicate (D3, D4)

    @Test("duplicating a closed project writes a uniquely named copy at once and selects nothing new")
    func duplicateAClosedProject() {
        let app = Self.twoProjects()
        let model = app.window()
        model.path = []

        model.duplicate(Self.second)

        let copy = app.store.saves.last
        #expect(app.store.saves.count == 1)
        #expect(copy?.id != Self.second)
        #expect(copy?.program == Self.named("Square Coil 2", Self.coil))
        #expect(model.projectID == Self.first)
        #expect(model.path == [])
        #expect(app.library.files.count == 3)
    }

    @Test("duplicating the open project copies the program on screen")
    func duplicateTheOpenProject() {
        let app = Self.twoProjects()
        let model = app.window()
        model.editor.apply(.renameProgram("Edited"))

        model.duplicate(Self.first)

        #expect(app.store.saves.last?.program == Self.named("Edited 2"))
        #expect(model.projectID == Self.first)
    }

    @Test("a duplicate that cannot be written says so and lists nothing new")
    func aFailedDuplicate() {
        let app = Self.twoProjects()
        let model = app.window()
        app.store.failsEverySave = true

        model.duplicate(Self.second)

        #expect(model.listState.notice == .duplicateFailed)
        #expect(app.library.files.count == 2)
    }

    // MARK: Delete (D9)

    @Test("asking to delete deletes nothing; confirming deletes exactly once")
    func deleteNeedsConfirmation() throws {
        let app = Self.twoProjects()
        let model = app.window()

        try model.requestDeletion(of: Self.row(Self.second, in: app))

        #expect(model.listState.pendingDeletion == PendingDeletion(id: Self.second, name: Self.coil.name))
        #expect(app.store.deletes.isEmpty)

        model.confirmDeletion()
        model.confirmDeletion()

        #expect(app.store.deletes == [Self.second])
        #expect(model.listState.pendingDeletion == nil)
        #expect(!app.library.files.contains { $0.id == Self.second })
        #expect(model.projectID == Self.first)
    }

    @Test("cancelling a delete deletes nothing")
    func cancellingDeletesNothing() throws {
        let app = Self.twoProjects()
        let model = app.window()
        try model.requestDeletion(of: Self.row(Self.second, in: app))

        model.cancelDeletion()
        model.confirmDeletion()

        #expect(app.store.deletes.isEmpty)
        #expect(model.listState.pendingDeletion == nil)
    }

    @Test("a failed delete leaves the row and the window as they were, and says so")
    func aFailedDeleteChangesNothing() throws {
        let app = Self.twoProjects()
        let model = app.window()
        app.store.failsDeletes = true
        try model.requestDeletion(of: Self.row(Self.first, in: app))

        model.confirmDeletion()

        #expect(model.listState.notice == .deleteFailed(name: Self.rosette.name))
        #expect(app.library.files.contains { $0.id == Self.first })
        #expect(model.projectID == Self.first)
        #expect(model.editor.program == Self.rosette)
    }

    @Test("deleting the open project leaves the window on a new blank draft, back at the list")
    func deletingTheOpenProject() throws {
        let app = Self.twoProjects()
        let model = app.window()
        model.path = [.script, .stage]
        try model.requestDeletion(of: Self.row(Self.first, in: app))

        model.confirmDeletion()

        #expect(app.store.deletes == [Self.first])
        #expect(model.projectID != Self.first)
        #expect(model.editor.program.name == "Design")
        #expect(model.path == [])
        #expect(app.remembered.id == nil)
        #expect(app.library.holders(of: Self.first).isEmpty)
        #expect(app.store.saves.isEmpty, "the new draft writes nothing until it changes")
    }

    @Test("a project another window holds is not deleted, and the user is told why")
    func aHeldProjectIsNotDeleted() throws {
        let app = Self.twoProjects()
        // Kept alive to the end: the registry holds windows weakly, so a discarded one holds nothing.
        let other = app.window(scene: Self.second)
        let model = app.window()
        try model.requestDeletion(of: Self.row(Self.second, in: app))

        model.confirmDeletion()

        #expect(app.store.deletes.isEmpty)
        #expect(model.listState.notice == .heldElsewhere(name: Self.coil.name))
        #expect(other.projectID == Self.second)
    }

    @Test("a refused file can be deleted from the list")
    func deletingARefusedFile() throws {
        let app = App([Self.first: .program(Self.rosette), Self.second: .refused(.corrupt, name: nil)])
        let model = app.window(scene: Self.first)
        try model.requestDeletion(of: Self.row(Self.second, in: app))

        model.confirmDeletion()

        #expect(app.store.deletes == [Self.second])
        #expect(app.library.failure(for: Self.second) == nil)
    }

    @Test("the notice goes once it has been read")
    func dismissingTheNotice() {
        let app = Self.twoProjects()
        let model = app.window()
        app.store.failsEverySave = true
        model.duplicate(Self.second)

        model.dismissListNotice()

        #expect(model.listState.notice == nil)
    }

    // MARK: Held by another window (D7)

    @Test("a project is held elsewhere only while another live window holds it")
    func heldElsewhere() {
        let app = Self.twoProjects()
        let model = app.window()
        #expect(!model.isHeldElsewhere(Self.first), "this window's own project")
        #expect(!model.isHeldElsewhere(Self.second))

        let other = app.window(scene: Self.second)
        #expect(model.isHeldElsewhere(Self.second))

        other.close()
        #expect(!model.isHeldElsewhere(Self.second))
    }
}
