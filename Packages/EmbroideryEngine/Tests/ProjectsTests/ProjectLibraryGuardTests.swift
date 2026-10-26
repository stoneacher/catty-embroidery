@testable import Projects
import EditorCore
import EmbroideryEngine
import Foundation
import Observation
import ProgramModel
import Samples
import Testing

// The guards the slice 4 review found unpinned (`swift-code-reviewer`'s surviving mutants and
// Codex's findings), on `ProjectLibraryTests`' fixtures.

// MARK: - Slice 4 review (`swift-code-reviewer` and Codex)

extension ProjectLibraryTests {
    /// ADR-037's M8b, per project: a save the block stopped is still *accepted*, so once the
    /// block lifts an older save cannot land over it.
    @Test("a save stopped by a block still supersedes an older one once the block lifts")
    func aBlockedSaveIsStillAccepted() {
        let store = InMemoryProjectStore([Self.first: .refused(.corrupt, name: nil)])
        let library = Self.library(store)
        let older = library.mintRevision()
        let newer = library.mintRevision()

        #expect(library.save(Self.coil, to: Self.first, revision: newer) == .blocked)
        store.entries[Self.first] = .program(Self.coil)
        #expect(library.open(Self.first) == .opened(Self.coil))

        #expect(library.save(Self.rosette, to: Self.first, revision: older) == .superseded)
        #expect(store.saves.isEmpty)
    }

    /// D11 protects a file that cannot be read at all, not only one that does not parse.
    @Test("a file that cannot be read blocks its project like a refused one")
    func anUnreadableFileBlocks() {
        let store = InMemoryProjectStore()
        let library = Self.library(store)
        store.entries[Self.first] = .unreadable

        #expect(library.open(Self.first) == .refused(.unreadable))
        #expect(library.save(Self.rosette, to: Self.first, revision: library.mintRevision()) == .blocked)
        #expect(store.entries[Self.first] == .unreadable)
    }

    /// One window's failed save is not cleared by another window opening the same project.
    @Test("opening a project leaves another window's save failure in place")
    func openingKeepsASaveFailure() {
        let store = InMemoryProjectStore([Self.first: .program(Self.rosette)])
        let library = Self.library(store)
        store.failingSaves = [Self.first]
        #expect(library.save(Self.coil, to: Self.first, revision: library.mintRevision()) == .failed)

        #expect(library.open(Self.first) == .opened(Self.rosette))

        #expect(library.failure(for: Self.first) == .saveFailed)
    }

    @Test("renaming a closed project whose file has turned refused blocks it")
    func renameProbesTheFile() throws {
        let store = InMemoryProjectStore([Self.first: .program(Self.rosette)])
        let library = Self.library(store)
        store.entries[Self.first] = .refused(.unsupportedVersion(2), name: "Future")

        #expect(try library.rename(Self.first, to: Self.name("Moon")) == .blocked)
        #expect(library.save(Self.coil, to: Self.first, revision: library.mintRevision()) == .blocked)
    }

    @Test("re-registering a window replaces the draft name it reserved")
    func reRegisteringReplacesTheDraftName() throws {
        let library = Self.library(InMemoryProjectStore())
        let owner = WindowOwner()
        let window = WindowToken()

        library.register(window, owner: owner, holding: Self.first, draftName: "Design")
        library.register(window, owner: owner, holding: Self.first, draftName: nil)

        #expect(try library.uniquedName(Self.name("Design")).value == "Design")
    }

    /// D7, enforced by the library as well as disabled in the list: a project another window
    /// holds is not renamed or deleted under it.
    @Test("a project another window holds cannot be renamed or deleted through the catalog")
    func aHeldProjectIsProtected() throws {
        let store = InMemoryProjectStore([Self.first: .program(Self.rosette)])
        let library = Self.library(store)
        let owner = WindowOwner()
        let holder = WindowToken()
        library.register(holder, owner: owner, holding: Self.first, draftName: nil)

        #expect(try library.rename(Self.first, to: Self.name("Moon")) == .held)
        #expect(throws: ProjectLibraryError.heldByAnotherWindow) {
            try library.delete(Self.first, requestedBy: WindowToken())
        }
        #expect(store.program(Self.first) == Self.rosette)

        try library.delete(Self.first, requestedBy: holder)
        #expect(store.entries[Self.first] == nil)
    }

    /// The summaries follow what `open` learns, so a row never shows a badge the file has lost,
    /// or a project that is gone.
    @Test("re-probing a file updates its summary")
    func reProbingUpdatesTheSummary() {
        let store = InMemoryProjectStore([
            Self.first: .refused(.corrupt, name: nil), Self.second: .refused(.corrupt, name: nil)
        ])
        store.entries[.fixed(3)] = .program(Self.named("Star"))
        let library = Self.library(store)

        store.entries[Self.first] = .program(Self.coil)
        store.entries[Self.second] = nil
        store.entries[.fixed(3)] = .refused(.unsupportedVersion(2), name: "Star")
        _ = library.open(Self.first)
        _ = library.open(Self.second)
        _ = library.open(.fixed(3))

        let inspections = Dictionary(uniqueKeysWithValues: library.files.map { ($0.id, $0.inspection) })
        #expect(inspections == [
            Self.first: .openable(Self.coil), .fixed(3): .refused(.unsupportedVersion(2), name: "Star")
        ])
    }

    @Test("a failed duplicate leaves no failure behind")
    func aFailedDuplicateLeavesNoFailure() {
        let store = InMemoryProjectStore()
        let expectedID = SequentialProjectIDs().make()
        store.failingSaves = [expectedID]
        let library = Self.library(store)

        #expect(library.duplicate(Self.rosette) == nil)
        #expect(library.failure(for: expectedID) == nil)
    }

    // MARK: Observation (D7: explicit, observable transitions)

    /// Whether `change` notifies an observer of what `read` reads.
    private static func notifies(_ read: @escaping () -> Void, when change: () -> Void) -> Bool {
        let fired = ObservationFlag()
        withObservationTracking(read, onChange: { fired.value = true })
        change()
        return fired.value
    }

    @Test("windows observe who holds a project, a project's failure, and the list")
    func transitionsAreObservable() {
        let store = InMemoryProjectStore()
        store.failingSaves = [Self.second]
        let library = Self.library(store)
        let owner = WindowOwner()

        #expect(Self.notifies({ _ = library.holders(of: Self.first) }, when: {
            library.register(WindowToken(), owner: owner, holding: Self.first, draftName: nil)
        }))
        #expect(Self.notifies({ _ = library.failure(for: Self.second) }, when: {
            library.save(Self.rosette, to: Self.second, revision: library.mintRevision())
        }))
        #expect(Self.notifies({ _ = library.files }, when: {
            library.save(Self.rosette, to: Self.first, revision: library.mintRevision())
        }))
    }
}

/// A flag an observation callback can set; the callback is `@Sendable`, so it cannot capture a
/// local `var`.
private final class ObservationFlag: @unchecked Sendable {
    var value = false
}

// MARK: - Handover review (Codex, PR #78 round 1)

/// A summary's date is the file's own (brief D1, ADR-050), not a time the library made up.
@MainActor
@Suite("Project library dates")
struct ProjectLibraryDateTests {
    private static let program = SampleLibrary[.squareCoil].program
    private static let invented = Date(timeIntervalSince1970: 1_000)

    private static func dateOnDisk(_ store: DocumentsProjectStore, _ id: ProjectID) throws -> Date? {
        try store.url(for: id).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    @Test("a saved project's summary carries the file's modification date")
    func aSaveCarriesTheFileDate() throws {
        try inDisposableDirectory { root in
            let store = DocumentsProjectStore(directory: root)
            let library = ProjectLibrary(store: store, lastOpened: .disposable(), now: { Self.invented })

            library.save(Self.program, to: .fixed(1), revision: library.mintRevision())

            let summary = try #require(library.files.first)
            #expect(summary.modified == (try Self.dateOnDisk(store, .fixed(1))))
            #expect(summary.modified != Self.invented)
        }
    }

    /// A file the launch listing did not see — written since, or missed by a listing that
    /// failed — enters the list with its own date when it is opened.
    @Test("a project first seen by opening it is listed with the file's modification date")
    func anOpenedFileCarriesItsDate() throws {
        try inDisposableDirectory { root in
            let store = DocumentsProjectStore(directory: root)
            let library = ProjectLibrary(store: store, lastOpened: .disposable(), now: { Self.invented })
            try store.save(Self.program, as: .fixed(2))
            let old = Date(timeIntervalSince1970: 1_600_000_000)
            let path = store.url(for: .fixed(2)).path
            try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: path)

            #expect(library.open(.fixed(2)) == .opened(Self.program))

            #expect(library.files.map(\.modified) == [old])
        }
    }
}
