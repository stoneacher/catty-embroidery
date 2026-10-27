@testable import Projects
import EditorCore
import EmbroideryEngine
import Foundation
import ProgramModel
import Samples
import Testing

/// M4's single working file becomes a project (project management slice 6, brief D5): written
/// to a fixed ID only if that ID has no file, then made the last opened, then removed. Each
/// step can fail on its own, and a replay at the next launch finishes only what is missing, so
/// an edit made to the migrated project in between is never overwritten.
@MainActor
@Suite("Legacy migration")
struct LegacyMigrationTests {
    static let rosette = SampleLibrary[.octagonRosette].program
    static let coil = SampleLibrary[.squareCoil].program
    static let migrated = ProjectID.legacyWorkingProgram
    static let defaultName = ProjectLibrary.fallbackName

    /// One launch: the legacy file, the project store and the last-opened default.
    @MainActor
    struct Launch {
        let legacy: InMemoryProgramStore
        let projects: InMemoryProjectStore
        let remembered: LastOpenedProject
        let library: ProjectLibrary

        init(
            legacy: InMemoryProgramStore,
            projects: InMemoryProjectStore = InMemoryProjectStore(),
            remembered: LastOpenedProject = .disposable()
        ) {
            self.legacy = legacy
            self.projects = projects
            self.remembered = remembered
            library = ProjectLibrary(store: projects, lastOpened: remembered, legacy: legacy)
        }

        /// The next process over the same files.
        func relaunch() -> Launch {
            Launch(legacy: legacy, projects: projects, remembered: remembered)
        }

        @discardableResult
        func migrate() -> ProgramLoadError? {
            library.migrateLegacyIfNeeded(defaultName: defaultName)
        }
    }

    static func named(_ name: String, _ program: Program = rosette) -> Program {
        var renamed = program
        renamed.name = name
        return renamed
    }

    // MARK: The three steps

    @Test("with no legacy file there is nothing to do")
    func noLegacyFile() {
        let launch = Launch(legacy: InMemoryProgramStore())

        #expect(launch.migrate() == nil)

        #expect(launch.projects.saves.isEmpty)
        #expect(launch.remembered.id == nil)
        #expect(launch.legacy.removeCount == 0)
    }

    @Test("the legacy program becomes the fixed-ID project, the last opened, and the file goes")
    func theLegacyProgramMigrates() {
        let launch = Launch(legacy: InMemoryProgramStore(stored: Self.rosette))

        #expect(launch.migrate() == nil)

        #expect(launch.projects.program(Self.migrated) == Self.rosette)
        #expect(launch.remembered.id == Self.migrated)
        #expect(launch.legacy.stored == nil)
        #expect(launch.library.files.map(\.id) == [Self.migrated])
    }

    /// The fixed ID is what makes a replay find its own earlier work.
    @Test("the migrated project's ID is the same in every process")
    func theIDIsFixed() {
        #expect(ProjectID.legacyWorkingProgram == ProjectID(uuidString: ProjectID.legacyWorkingProgram.uuidString))
        let first = Launch(legacy: InMemoryProgramStore(stored: Self.rosette))
        let second = Launch(legacy: InMemoryProgramStore(stored: Self.coil))

        first.migrate()
        second.migrate()

        #expect(first.projects.program(Self.migrated) == Self.rosette)
        #expect(second.projects.program(Self.migrated) == Self.coil)
    }

    // MARK: Replays (a crash or a failure between steps)

    @Test("a replay after the project was written finishes the last opened and the removal")
    func replayAfterTheWrite() {
        let launch = Launch(
            legacy: InMemoryProgramStore(stored: Self.rosette),
            projects: InMemoryProjectStore([Self.migrated: .program(Self.rosette)])
        )

        launch.migrate()

        #expect(launch.projects.saves.isEmpty, "the project is not written again")
        #expect(launch.remembered.id == Self.migrated)
        #expect(launch.legacy.stored == nil)
    }

    @Test("a replay after the last opened was set finishes the removal")
    func replayAfterLastOpened() {
        let remembered = LastOpenedProject.disposable()
        remembered.id = Self.migrated
        let launch = Launch(
            legacy: InMemoryProgramStore(stored: Self.rosette),
            projects: InMemoryProjectStore([Self.migrated: .program(Self.rosette)]),
            remembered: remembered
        )

        launch.migrate()

        #expect(launch.projects.saves.isEmpty)
        #expect(launch.legacy.stored == nil)
    }

    @Test("a failed removal leaves the file for the next launch, which removes it")
    func aFailedRemovalIsReplayed() {
        let legacy = InMemoryProgramStore(stored: Self.rosette)
        legacy.failsRemove = true
        let first = Launch(legacy: legacy)
        first.migrate()
        #expect(first.projects.program(Self.migrated) == Self.rosette)
        #expect(legacy.stored == Self.rosette, "the premise: the removal failed")

        legacy.failsRemove = false
        let second = first.relaunch()
        second.migrate()

        #expect(legacy.stored == nil)
        #expect(second.projects.saves.count == 1, "written once, in the first launch")
    }

    /// The order is the safety: the file goes only once its program is safely a project. A
    /// write that fails leaves everything for the next launch.
    @Test("a failed project write keeps the legacy file and changes nothing else")
    func aFailedWriteKeepsTheLegacyFile() {
        let projects = InMemoryProjectStore()
        projects.failingSaves = [Self.migrated]
        let first = Launch(legacy: InMemoryProgramStore(stored: Self.rosette), projects: projects)

        first.migrate()

        #expect(first.legacy.stored == Self.rosette)
        #expect(first.legacy.removeCount == 0)
        #expect(first.remembered.id == nil)

        projects.failingSaves = []
        let second = first.relaunch()
        second.migrate()
        #expect(projects.program(Self.migrated) == Self.rosette)
        #expect(second.legacy.stored == nil)
    }

    /// The case D5 exists for: the user edited the migrated project after a migration whose
    /// removal failed, and the replay must not put the old legacy program back.
    @Test("a migrated project edited before a replay is never overwritten")
    func anEditedProjectIsKept() {
        let edited = Self.named("Edited since")
        let launch = Launch(
            legacy: InMemoryProgramStore(stored: Self.rosette),
            projects: InMemoryProjectStore([Self.migrated: .program(edited)])
        )

        launch.migrate()

        #expect(launch.projects.program(Self.migrated) == edited)
        #expect(launch.legacy.stored == nil)
    }

    /// A replay must not take "last opened" from a project the user has opened since.
    @Test("a replay does not take the last opened from a project opened since")
    func aReplayKeepsANewerLastOpened() {
        let other = ProjectID.fixed(7)
        let remembered = LastOpenedProject.disposable()
        remembered.id = other
        let launch = Launch(
            legacy: InMemoryProgramStore(stored: Self.rosette),
            projects: InMemoryProjectStore([Self.migrated: .program(Self.rosette), other: .program(Self.coil)]),
            remembered: remembered
        )

        launch.migrate()

        #expect(launch.remembered.id == other)
        #expect(launch.legacy.stored == nil)
    }

    // MARK: Names

    @Test("a legacy program with no valid name is given the default", arguments: ["", "far too long a name"])
    func anInvalidNameGetsTheDefault(_ name: String) {
        let launch = Launch(legacy: InMemoryProgramStore(stored: Self.named(name)))

        launch.migrate()

        #expect(launch.projects.program(Self.migrated) == Self.named(Self.defaultName.value))
    }

    // MARK: Refused and repeated

    @Test("a refused legacy file stays where it is, and is reported once per process")
    func aRefusedLegacyFileStays() {
        let legacy = InMemoryProgramStore()
        legacy.loadError = .document(.unsupportedVersion(2))
        let launch = Launch(legacy: legacy)

        #expect(launch.migrate() == .document(.unsupportedVersion(2)))
        #expect(launch.migrate() == nil, "a second window is not told again")

        #expect(legacy.removeCount == 0)
        #expect(legacy.setAsideCount == 0)
        #expect(launch.projects.saves.isEmpty)
    }

    @Test("several windows make one migration attempt")
    func oneAttemptPerProcess() {
        let launch = Launch(legacy: InMemoryProgramStore(stored: Self.rosette))

        launch.migrate()
        launch.migrate()

        #expect(launch.legacy.loadCount == 1)
    }
}
