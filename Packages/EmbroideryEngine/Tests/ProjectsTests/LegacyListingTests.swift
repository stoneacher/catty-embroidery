import EditorCore
import Foundation
import ProgramModel
@testable import Projects
import Samples
import Testing

/// A refused legacy file is listed, so the list can delete it (project management slice 7,
/// closing slice 6's known gap): until now it was alerted for at every launch with nothing in
/// the app able to clear it. It is listed under `ProjectID.legacyWorkingProgram`, whose delete
/// already removes the legacy file first (slice 6 review).
@MainActor
@Suite("Legacy listing")
struct LegacyListingTests {
    typealias Launch = LegacyMigrationTests.Launch
    static let migrated = ProjectID.legacyWorkingProgram
    static let migrationTime = Date(timeIntervalSince1970: 1_800_000_000)

    static func refusedLegacy(_ error: ProgramLoadError) -> InMemoryProgramStore {
        let legacy = InMemoryProgramStore()
        legacy.loadError = error
        return legacy
    }

    static func library(over launch: Launch) -> ProjectLibrary {
        ProjectLibrary(
            store: launch.projects,
            lastOpened: launch.remembered,
            legacy: launch.legacy,
            now: { migrationTime }
        )
    }

    @Test("a refused legacy file is listed under the fixed ID, refused, unnamed, and blocked")
    func aRefusedLegacyFileIsListed() {
        let launch = Launch(legacy: Self.refusedLegacy(.document(.unsupportedVersion(2))))
        let library = Self.library(over: launch)

        library.migrateLegacyIfNeeded(defaultName: LegacyMigrationTests.defaultName)

        #expect(library.files == [
            ProjectFile(
                id: Self.migrated,
                inspection: .refused(.unsupportedVersion(2), name: nil),
                modified: Self.migrationTime
            )
        ])
        #expect(library.failure(for: Self.migrated) == .refusedDocument)
        #expect(library
            .save(LegacyMigrationTests.rosette, to: Self.migrated, revision: library.mintRevision()) == .blocked)
        #expect(launch.projects.saves.isEmpty)
    }

    @Test("an unreadable legacy file is listed as damaged")
    func anUnreadableLegacyFileIsDamaged() {
        let launch = Launch(legacy: Self.refusedLegacy(.unreadable))
        let library = Self.library(over: launch)

        library.migrateLegacyIfNeeded(defaultName: LegacyMigrationTests.defaultName)

        #expect(library.files.map(\.inspection) == [.refused(.corrupt, name: nil)])
    }

    @Test("deleting the listed legacy file removes it, and the next launch has nothing to migrate or list")
    func deletingTheRowRemovesTheLegacyFile() throws {
        let launch = Launch(legacy: Self.refusedLegacy(.document(.corrupt)))
        let library = Self.library(over: launch)
        library.migrateLegacyIfNeeded(defaultName: LegacyMigrationTests.defaultName)
        #expect(library.files.map(\.id) == [Self.migrated])

        try library.delete(Self.migrated)

        #expect(library.files.isEmpty)
        #expect(launch.legacy.removeCount == 1)
        let next = Self.library(over: launch.relaunch())
        #expect(next.migrateLegacyIfNeeded(defaultName: LegacyMigrationTests.defaultName) == nil)
        #expect(next.files.isEmpty)
    }

    @Test("a refused legacy file beside an existing fixed-ID project leaves that project's row alone")
    func anExistingMigratedProjectKeepsItsRow() {
        let projects = InMemoryProjectStore([Self.migrated: .program(LegacyMigrationTests.coil)])
        let launch = Launch(legacy: Self.refusedLegacy(.document(.corrupt)), projects: projects)
        let library = Self.library(over: launch)

        library.migrateLegacyIfNeeded(defaultName: LegacyMigrationTests.defaultName)

        #expect(library.files.map(\.inspection) == [.openable(LegacyMigrationTests.coil)])
        #expect(library.failure(for: Self.migrated) == nil)
    }

    /// The listed row is the legacy file alone: no project file stands behind it, so its delete
    /// must not depend on the project store, whose failure would otherwise be reported after the
    /// legacy file was already gone (D9; Codex, PR 2 round 1).
    @Test("deleting the listed legacy file does not depend on the project store")
    func deletingTheRowNeedsOnlyTheLegacyFile() throws {
        let launch = Launch(legacy: Self.refusedLegacy(.document(.corrupt)))
        let library = Self.library(over: launch)
        library.migrateLegacyIfNeeded(defaultName: LegacyMigrationTests.defaultName)
        launch.projects.failsDeletes = true

        try library.delete(Self.migrated)

        #expect(library.files.isEmpty)
        #expect(launch.legacy.removeCount == 1)
        #expect(launch.projects.deletes.isEmpty)
    }

    @Test("a legacy file that cannot be removed leaves its row, its block and its file")
    func aFailedLegacyRemovalChangesNothing() {
        let launch = Launch(legacy: Self.refusedLegacy(.document(.corrupt)))
        let library = Self.library(over: launch)
        library.migrateLegacyIfNeeded(defaultName: LegacyMigrationTests.defaultName)
        launch.legacy.failsRemove = true

        #expect(throws: (any Error).self) { try library.delete(Self.migrated) }

        #expect(library.files.map(\.id) == [Self.migrated])
        #expect(library.failure(for: Self.migrated) == .refusedDocument)
    }
}
