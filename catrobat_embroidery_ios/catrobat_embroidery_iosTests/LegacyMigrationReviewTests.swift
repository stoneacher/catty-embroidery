@testable import catrobat_embroidery_ios
import EditorCore
import EmbroideryEngine
import Foundation
import ProgramModel
import Samples
import Testing

// The migration paths the slice 6 review found unguarded or unpinned (Codex and
// `swift-code-reviewer`), on `LegacyMigrationTests`' fixtures.

extension LegacyMigrationTests {
    /// Codex, slice 6 (High): with the fixed-ID file unopenable, the legacy file may be the
    /// only good copy of the design, so it stays, and nothing points at the unopenable file.
    @Test("an unopenable file at the fixed ID keeps the legacy file and the last opened", arguments: [
        InMemoryProjectStore.Entry.refused(.corrupt, name: nil), .unreadable
    ])
    func anUnopenableFixedIDKeepsEverything(_ entry: InMemoryProjectStore.Entry) {
        let launch = Launch(
            legacy: InMemoryProgramStore(stored: Self.rosette),
            projects: InMemoryProjectStore([Self.migrated: entry])
        )

        launch.migrate()

        #expect(launch.projects.entries[Self.migrated] == entry)
        #expect(launch.legacy.stored == Self.rosette)
        #expect(launch.legacy.removeCount == 0)
        #expect(launch.remembered.id == nil)
    }

    /// Codex, slice 6: a generated name is made unique (brief D4), the default included.
    @Test("the default given to an unnamed legacy program is made unique")
    func theDefaultIsUniqued() {
        let launch = Launch(
            legacy: InMemoryProgramStore(stored: Self.named("")),
            projects: InMemoryProjectStore([.fixed(9): .program(Self.named(Self.defaultName.value, Self.coil))])
        )

        launch.migrate()

        #expect(launch.projects.program(Self.migrated)?.name == "\(Self.defaultName.value) 2")
    }

    /// Codex, slice 6: two refusals in one launch are both told, one after the other.
    @Test("a refused legacy file and a refused scene project are both alerted for")
    func twoRefusalsAreBothTold() throws {
        let legacy = InMemoryProgramStore()
        legacy.loadError = .document(.corrupt)
        let scene = ProjectID.fixed(3)
        let launch = Launch(
            legacy: legacy, projects: InMemoryProjectStore([scene: .refused(.unsupportedVersion(2), name: nil)])
        )
        let model = AppModel(library: launch.library)

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

    /// `swift-code-reviewer`, slice 6: a replay that writes the project still does not take
    /// "last opened" from a project the user opened while the write was failing.
    @Test("a replay that writes the project leaves a newer last opened alone")
    func aWritingReplayKeepsANewerLastOpened() {
        let projects = InMemoryProjectStore()
        projects.failingSaves = [Self.migrated]
        let first = Launch(legacy: InMemoryProgramStore(stored: Self.rosette), projects: projects)
        first.migrate()
        let other = ProjectID.fixed(7)
        first.remembered.id = other

        projects.failingSaves = []
        let second = first.relaunch()
        second.migrate()

        #expect(projects.program(Self.migrated) == Self.rosette)
        #expect(second.remembered.id == other)
        #expect(second.legacy.stored == nil)
    }

    /// `swift-code-reviewer`, slice 6: a migrated project the user deleted must not come back
    /// from a legacy file whose removal failed.
    @Test("deleting the migrated project removes a leftover legacy file, so it is not migrated again")
    func deletingTheMigratedProjectRemovesTheLegacyFile() throws {
        let legacy = InMemoryProgramStore(stored: Self.rosette)
        legacy.failsRemove = true
        let first = Launch(legacy: legacy)
        first.migrate()
        legacy.failsRemove = false

        try first.library.delete(Self.migrated)
        let second = first.relaunch()
        second.migrate()

        #expect(legacy.stored == nil)
        #expect(second.projects.entries[Self.migrated] == nil)
        #expect(second.remembered.id == nil)
    }

    @Test("a delete of the migrated project whose legacy removal fails changes nothing")
    func aFailedLegacyRemovalStopsTheDelete() {
        let legacy = InMemoryProgramStore(stored: Self.rosette)
        legacy.failsRemove = true
        let launch = Launch(legacy: legacy)
        launch.migrate()

        #expect(throws: (any Error).self) {
            try launch.library.delete(Self.migrated)
        }

        #expect(launch.projects.program(Self.migrated) == Self.rosette)
        #expect(legacy.stored == Self.rosette)
    }

    @Test("a failed migration write leaves no failure behind, since no window holds the project")
    func aFailedWriteLeavesNoFailure() {
        let projects = InMemoryProjectStore()
        projects.failingSaves = [Self.migrated]
        let launch = Launch(legacy: InMemoryProgramStore(stored: Self.rosette), projects: projects)

        launch.migrate()

        #expect(launch.library.failure(for: Self.migrated) == nil)
    }
}
