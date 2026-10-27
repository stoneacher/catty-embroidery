@testable import catrobat_embroidery_ios
import EditorCore
import Foundation
import ProgramModel
import Projects
import Samples
import StagePreview
import Testing

/// Tapping a project in the list opens it in the window (project management slice 7; brief
/// D3, D6, D7): read from its file, held, the last opened, and on its script — writing nothing.
/// Driven through `AppModel` for the reason `ProjectWiringTests` gives.
@MainActor
@Suite("Project opening")
struct ProjectOpeningTests {
    typealias App = ProjectWiringTests.App
    static let rosette = SampleLibrary[.octagonRosette].program
    static let coil = SampleLibrary[.squareCoil].program
    static let first = ProjectID.fixed(1)
    static let second = ProjectID.fixed(2)

    static func twoProjects() -> App {
        App([first: .program(rosette), second: .program(coil)], lastOpened: first)
    }

    @Test("opening a project loads it, holds it, makes it the last opened and shows its script")
    func openingAProject() {
        let app = Self.twoProjects()
        let model = app.window()
        model.path = []

        model.openProject(Self.second)

        #expect(model.projectID == Self.second)
        #expect(model.editor.program == Self.coil)
        #expect(!model.editor.canUndo)
        #expect(model.path == [.script])
        #expect(model.selection?.provenance == nil)
        #expect(app.remembered.id == Self.second)
        #expect(app.library.holders(of: Self.second) == [model.window])
        #expect(app.library.holders(of: Self.first).isEmpty)
    }

    @Test("opening a project writes nothing")
    func openingWritesNothing() {
        let app = Self.twoProjects()
        let model = app.window()

        model.openProject(Self.second)
        model.sceneDidLeaveActive()

        #expect(app.store.saves.isEmpty)
    }

    @Test("opening a project is a new selection and discards the previous run")
    func openingDiscardsTheRun() async {
        let app = Self.twoProjects()
        let model = app.window()
        let before = model.selection?.generation
        model.play()
        for _ in 0 ..< 100_000 where model.runner.run.display.isEmpty {
            await Task.yield()
        }

        model.openProject(Self.second)

        #expect(model.selection?.generation != before)
        #expect(model.runner.run.state == .idle)
        #expect(model.runner.run.display.isEmpty)
    }

    @Test("the opened project's first change is saved to it")
    func aChangeSavesToTheOpenedProject() {
        let app = Self.twoProjects()
        let model = app.window()

        model.openProject(Self.second)
        model.editor.apply(.renameProgram("Opened"))

        #expect(app.store.saves.map(\.id) == [Self.second])
    }

    @Test("tapping the open project only shows its script, keeping its history")
    func tappingTheOpenProject() {
        let app = Self.twoProjects()
        let model = app.window()
        model.editor.apply(.renameProgram("Edited"))
        let generation = model.selection?.generation
        model.path = []

        model.openProject(Self.first)

        #expect(model.editor.program.name == "Edited")
        #expect(model.editor.canUndo)
        #expect(model.selection?.generation == generation)
        #expect(model.path == [.script])
    }

    @Test("a project refused on opening leaves the window where it is, and its row badged")
    func aRefusedProjectStays() {
        let app = Self.twoProjects()
        let model = app.window()
        app.store.entries[Self.second] = .refused(.corrupt, name: "Coil")

        model.openProject(Self.second)

        #expect(model.projectID == Self.first)
        #expect(model.editor.program == Self.rosette)
        // The library keeps the name it last read: the file it read now has none it can trust.
        let row = app.library.files.first { $0.id == Self.second }
        #expect(row?.inspection == .refused(.corrupt, name: Self.coil.name))
        #expect(app.remembered.id == Self.first)
    }

    @Test("a project deleted elsewhere leaves the window where it is, and its row goes")
    func aMissingProjectStays() {
        let app = Self.twoProjects()
        let model = app.window()
        app.store.entries[Self.second] = nil

        model.openProject(Self.second)

        #expect(model.projectID == Self.first)
        #expect(!app.library.files.contains { $0.id == Self.second })
    }

    @Test("opening another project retries a failed save first, and stays if it fails again")
    func aFailedSaveKeepsTheWindow() {
        let app = Self.twoProjects()
        let model = app.window()
        app.store.failingSaves = [Self.first]
        model.editor.apply(.renameProgram("Unsaved"))

        model.openProject(Self.second)

        #expect(model.projectID == Self.first)
        #expect(model.editor.program.name == "Unsaved")

        app.store.failingSaves = []
        model.openProject(Self.second)

        #expect(model.projectID == Self.second)
        #expect(app.store.program(Self.first)?.name == "Unsaved")
    }

    @Test("a project another window holds can be opened here too")
    func aHeldProjectOpens() {
        let app = Self.twoProjects()
        let other = app.window(scene: Self.second)
        // On `first` by name: opening `second` above made it the last opened (feature review).
        let model = app.window(scene: Self.first)
        #expect(model.projectID == Self.first)

        model.openProject(Self.second)

        #expect(model.projectID == Self.second)
        #expect(app.library.holders(of: Self.second) == [other.window, model.window])
    }

    // MARK: Switching from the stage (feature review, PR 2)

    /// On an iPad resized from compact, `path` can still hold the stage when the sidebar opens a
    /// project; leaving the stage commits the field, which must not reach the new project.
    @Test("opening a project while the stage is on the path writes nothing and keeps its name")
    func openingFromTheStage() {
        let app = Self.twoProjects()
        let model = app.window()
        model.path = [.script, .stage]

        model.openProject(Self.second)

        #expect(model.editor.program == Self.coil)
        #expect(model.nameDraft == Self.coil.name)
        #expect(app.store.saves.isEmpty)
    }

    @Test("a valid name typed but not yet committed goes to the project being left", arguments: Switch.allCases)
    func aTypedNameGoesToTheProjectLeft(_ route: Switch) {
        let app = Self.twoProjects()
        let model = app.window()
        model.path = [.script, .stage]
        model.nameDraft = "Typed"

        route.perform(on: model)

        #expect(app.store.program(Self.first)?.name == "Typed")
        #expect(model.editor.program.name != "Typed")
        #expect(app.store.program(Self.second) == Self.coil)
    }

    enum Switch: CaseIterable {
        case openProject, pickSample, newDesign

        @MainActor
        func perform(on model: AppModel) {
            switch self {
            case .openProject: model.openProject(ProjectOpeningTests.second)
            case .pickSample: model.select(SampleLibrary[.arcFlower])
            case .newDesign: model.newDesign()
            }
        }
    }
}
