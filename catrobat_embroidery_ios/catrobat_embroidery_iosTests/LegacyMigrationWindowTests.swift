@testable import catrobat_embroidery_ios
import EditorCore
import Foundation
import ProgramModel
import Projects
import Samples
import Testing

/// The legacy migration as a window sees it (project management slice 6, brief D5): the three
/// claims about `AppModel`. The migration's own suite moved into the `Projects` package with
/// US-329; these stay here because they drive the window.
@MainActor
@Suite("Legacy migration through a window")
struct LegacyMigrationWindowTests {
    private static let rosette = SampleLibrary[.octagonRosette].program
    private static let migrated = ProjectID.legacyWorkingProgram

    private static func library(
        legacy: InMemoryProgramStore, projects: InMemoryProjectStore = InMemoryProjectStore()
    ) -> ProjectLibrary {
        ProjectLibrary(store: projects, lastOpened: .disposable(), legacy: legacy)
    }

    @Test("a window launched over a legacy file opens the migrated project")
    func aWindowOpensTheMigratedProject() {
        let projects = InMemoryProjectStore()
        let legacy = InMemoryProgramStore(stored: Self.rosette)
        let model = AppModel(library: Self.library(legacy: legacy, projects: projects))

        model.launch(sceneID: nil)

        #expect(model.projectID == Self.migrated)
        #expect(model.editor.program == Self.rosette)
        #expect(projects.saves.count == 1, "the migration's write, and nothing else")
    }

    @Test("a window launched over a refused legacy file says so, and opens a draft")
    func aWindowReportsARefusedLegacyFile() throws {
        let legacy = InMemoryProgramStore()
        legacy.loadError = .document(.corrupt)
        let model = AppModel(library: Self.library(legacy: legacy))

        model.launch(sceneID: nil)

        #expect(try #require(model.launchRefusal).reason == .document(.corrupt))
        #expect(model.projectID != Self.migrated)
    }

    /// Codex, slice 6: two refusals in one launch are both told, one after the other.
    @Test("a refused legacy file and a refused scene project are both alerted for")
    func twoRefusalsAreBothTold() throws {
        let legacy = InMemoryProgramStore()
        legacy.loadError = .document(.corrupt)
        let scene = ProjectID.fixed(3)
        let projects = InMemoryProjectStore([scene: .refused(.unsupportedVersion(2), name: nil)])
        let model = AppModel(library: Self.library(legacy: legacy, projects: projects))

        model.launch(sceneID: scene)

        let first = try #require(model.launchRefusal).reason
        model.dismissLaunchRefusal()
        let second = try #require(model.launchRefusal).reason
        model.dismissLaunchRefusal()
        #expect(Set([first, second].map { "\($0)" }).count == 2)
        #expect([first, second].contains(.document(.corrupt)))
        #expect([first, second].contains(.document(.unsupportedVersion(2))))
        #expect(model.launchRefusal == nil)
    }
}
