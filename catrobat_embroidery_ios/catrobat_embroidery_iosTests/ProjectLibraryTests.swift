@testable import catrobat_embroidery_ios
import EditorCore
import EmbroideryEngine
import Foundation
import Observation
import ProgramModel
import Samples
import Testing

/// The app-scoped guard on every project file (project management slice 4, brief D3, D7, D9,
/// D11), against the real coordinator: the store holds no policy, so a green here cannot be a
/// double's own copy of a rule passing. ADR-037's revision rule, now per project.
@MainActor
@Suite("Project library")
struct ProjectLibraryTests {
    static let rosette = SampleLibrary[.octagonRosette].program
    static let coil = SampleLibrary[.squareCoil].program
    static let first = ProjectID.fixed(1)
    static let second = ProjectID.fixed(2)
    static let createdAt = Date(timeIntervalSince1970: 1_800_000_000)

    static func library(
        _ store: InMemoryProjectStore,
        ids: SequentialProjectIDs = SequentialProjectIDs()
    ) -> ProjectLibrary {
        ProjectLibrary(store: store, makeID: { ids.make() }, now: { createdAt })
    }

    static func named(_ name: String, _ program: Program = rosette) -> Program {
        var renamed = program
        renamed.name = name
        return renamed
    }

    static func name(_ raw: String) throws -> DesignName {
        try DesignName.validating(raw).get()
    }

    // MARK: Revisions, per project

    @Test("each minted revision is newer than every one before it")
    func revisionsIncrease() {
        let library = Self.library(InMemoryProjectStore())

        let revisions = (0 ..< 3).map { _ in library.mintRevision() }

        #expect(revisions[0] < revisions[1])
        #expect(revisions[1] < revisions[2])
    }

    @Test("a current save is written and listed without a rescan")
    func aCurrentSaveIsWrittenAndListed() {
        let store = InMemoryProjectStore()
        let library = Self.library(store)

        let outcome = library.save(Self.rosette, to: Self.first, revision: library.mintRevision())

        #expect(outcome == .written)
        #expect(store.program(Self.first) == Self.rosette)
        let expected = ProjectFile(id: Self.first, inspection: .openable(Self.rosette), modified: Self.createdAt)
        #expect(library.files == [expected])
        #expect(store.listCount == 1)
    }

    @Test("within one project, an older save arriving last is dropped")
    func anOlderSaveIsDropped() {
        let store = InMemoryProjectStore()
        let library = Self.library(store)
        let older = library.mintRevision()
        let newer = library.mintRevision()

        #expect(library.save(Self.coil, to: Self.first, revision: newer) == .written)
        #expect(library.save(Self.rosette, to: Self.first, revision: older) == .superseded)

        #expect(store.program(Self.first) == Self.coil)
        #expect(store.saves.count == 1)
    }

    /// Brief D7: revisions are global, but what one project accepted says nothing about another.
    @Test("a newer save to one project never supersedes an older save to another")
    func projectsDoNotSupersedeEachOther() {
        let store = InMemoryProjectStore()
        let library = Self.library(store)
        let older = library.mintRevision()
        let newer = library.mintRevision()

        #expect(library.save(Self.coil, to: Self.second, revision: newer) == .written)
        #expect(library.save(Self.rosette, to: Self.first, revision: older) == .written)

        #expect(store.program(Self.first) == Self.rosette)
        #expect(store.program(Self.second) == Self.coil)
    }

    @Test("a save repeating the accepted revision is written again")
    func anEqualRevisionIsWrittenAgain() {
        let store = InMemoryProjectStore()
        let library = Self.library(store)
        let revision = library.mintRevision()

        library.save(Self.rosette, to: Self.first, revision: revision)
        let outcome = library.save(Self.coil, to: Self.first, revision: revision)

        #expect(outcome == .written)
        #expect(store.program(Self.first) == Self.coil)
    }

    // MARK: Failures, per project

    @Test("a failed save shows only on its project, and another's success does not clear it")
    func failuresArePerProject() {
        let store = InMemoryProjectStore()
        store.failingSaves = [Self.first]
        let library = Self.library(store)

        #expect(library.save(Self.rosette, to: Self.first, revision: library.mintRevision()) == .failed)
        #expect(library.save(Self.coil, to: Self.second, revision: library.mintRevision()) == .written)

        #expect(library.failure(for: Self.first) == .saveFailed)
        #expect(library.failure(for: Self.second) == nil)
        #expect(!library.files.contains { $0.id == Self.first })

        store.failingSaves = []
        #expect(library.save(Self.rosette, to: Self.first, revision: library.mintRevision()) == .written)
        #expect(library.failure(for: Self.first) == nil)
    }

    @Test("a newer save that failed still supersedes an older one")
    func acceptedIsNotWritten() {
        let store = InMemoryProjectStore()
        let library = Self.library(store)
        let older = library.mintRevision()
        let newer = library.mintRevision()

        store.failingSaves = [Self.first]
        #expect(library.save(Self.coil, to: Self.first, revision: newer) == .failed)
        store.failingSaves = []

        #expect(library.save(Self.rosette, to: Self.first, revision: older) == .superseded)
        #expect(store.program(Self.first) == nil)
    }

    // MARK: Refused files (D11)

    @Test("opening a refused file blocks every save to it, and only to it")
    func aRefusalBlocksItsProject() {
        let store = InMemoryProjectStore()
        let library = Self.library(store)
        // Refused only after the listing, so it is the opening that must install the block.
        store.entries[Self.first] = .refused(.unsupportedVersion(2), name: "Future")

        #expect(library.open(Self.first) == .refused(.document(.unsupportedVersion(2))))
        #expect(library.save(Self.rosette, to: Self.first, revision: library.mintRevision()) == .blocked)
        #expect(library.save(Self.coil, to: Self.second, revision: library.mintRevision()) == .written)

        #expect(store.entries[Self.first] == .refused(.unsupportedVersion(2), name: "Future"))
        #expect(library.failure(for: Self.first) == .refusedDocument)
        #expect(library.failure(for: Self.second) == nil)
    }

    /// The block must not depend on some window having tried to open the file: the list's scan
    /// found it first.
    @Test("a refused file found by the first listing is blocked before anyone opens it")
    func aListedRefusalBlocks() {
        let store = InMemoryProjectStore([Self.first: .refused(.corrupt, name: nil)])
        let library = Self.library(store)

        #expect(library.save(Self.rosette, to: Self.first, revision: library.mintRevision()) == .blocked)
        #expect(store.saves.isEmpty)
    }

    @Test("a refused file re-probed as openable, or gone, lifts its block")
    func reProbingLiftsTheBlock() {
        let damaged = InMemoryProjectStore.Entry.refused(.corrupt, name: nil)
        let store = InMemoryProjectStore([Self.first: damaged, Self.second: damaged])
        let library = Self.library(store)

        store.entries[Self.first] = .program(Self.coil)
        store.entries[Self.second] = nil
        #expect(library.open(Self.first) == .opened(Self.coil))
        #expect(library.open(Self.second) == .missing)

        #expect(library.failure(for: Self.first) == nil)
        #expect(library.save(Self.rosette, to: Self.first, revision: library.mintRevision()) == .written)
        #expect(library.save(Self.rosette, to: Self.second, revision: library.mintRevision()) == .written)
    }

    // MARK: Delete (D9)

    @Test("a delete removes the file and the summary, and a later save is refused as deleted")
    func aSaveAfterDeleteStaysDeleted() throws {
        let store = InMemoryProjectStore([Self.first: .program(Self.rosette), Self.second: .program(Self.coil)])
        let library = Self.library(store)
        let pending = library.mintRevision()

        try library.delete(Self.first)

        #expect(store.entries[Self.first] == nil)
        #expect(library.files.map(\.id) == [Self.second])
        #expect(library.save(Self.rosette, to: Self.first, revision: pending) == .deleted)
        #expect(library.save(Self.rosette, to: Self.first, revision: library.mintRevision()) == .deleted)
        #expect(store.entries[Self.first] == nil)
        #expect(store.saves.isEmpty)
    }

    /// The tombstone against a real disk: the seeded file is really gone, and stays gone.
    @Test("on a real disk, a save after a delete leaves the file deleted")
    func aSaveAfterDeleteOnARealDisk() throws {
        try inDisposableDirectory { root in
            let store = DocumentsProjectStore(directory: root)
            try store.save(Self.rosette, as: Self.first)
            let library = ProjectLibrary(store: store, makeID: { ProjectID(UUID()) }, now: { Self.createdAt })

            try library.delete(Self.first)
            let outcome = library.save(Self.coil, to: Self.first, revision: library.mintRevision())

            #expect(outcome == .deleted)
            #expect(!FileManager.default.fileExists(atPath: store.url(for: Self.first).path))
        }
    }

    @Test("a delete that fails changes nothing")
    func aFailedDeleteChangesNothing() {
        let store = InMemoryProjectStore([Self.first: .program(Self.rosette)])
        store.failsDeletes = true
        let library = Self.library(store)
        let before = library.files

        #expect(throws: InMemoryProjectStore.Failure.self) {
            try library.delete(Self.first)
        }

        #expect(library.files == before)
        #expect(store.program(Self.first) == Self.rosette)
        #expect(library.save(Self.coil, to: Self.first, revision: library.mintRevision()) == .written)
    }

    @Test("deleting a refused file clears its block and its failure")
    func deletingARefusedFile() throws {
        let store = InMemoryProjectStore([Self.first: .refused(.corrupt, name: "Old")])
        let library = Self.library(store)
        #expect(library.save(Self.rosette, to: Self.first, revision: library.mintRevision()) == .blocked)

        try library.delete(Self.first)

        #expect(library.failure(for: Self.first) == nil)
        #expect(library.files.isEmpty)
    }

}

// MARK: - Registry (D7)

extension ProjectLibraryTests {

    @Test("registering, switching and closing are visible in who holds a project")
    func registryTransitions() {
        let library = Self.library(InMemoryProjectStore())
        let owner = WindowOwner()
        let window = WindowToken()

        library.register(window, owner: owner, holding: Self.first, draftName: nil)
        #expect(library.holders(of: Self.first) == [window])

        library.register(window, owner: owner, holding: Self.second, draftName: nil)
        #expect(library.holders(of: Self.first).isEmpty)
        #expect(library.holders(of: Self.second) == [window])

        library.unregister(window, from: Self.second)
        #expect(library.holders(of: Self.second).isEmpty)
    }

    @Test("two windows on one project both hold it, and closing one leaves the other")
    func twoWindowsOnOneProject() {
        let library = Self.library(InMemoryProjectStore())
        let owners = (WindowOwner(), WindowOwner())
        let (left, right) = (WindowToken(), WindowToken())

        library.register(left, owner: owners.0, holding: Self.first, draftName: nil)
        library.register(right, owner: owners.1, holding: Self.first, draftName: nil)
        library.unregister(left, from: Self.first)

        #expect(library.holders(of: Self.first) == [right])
    }

    /// A window that has moved on from P to Q must not lose Q to a late "leaving P".
    @Test("a stale unregister does not remove the window's current project")
    func aStaleUnregisterKeepsTheSuccessor() {
        let library = Self.library(InMemoryProjectStore())
        let owner = WindowOwner()
        let window = WindowToken()

        library.register(window, owner: owner, holding: Self.first, draftName: nil)
        library.register(window, owner: owner, holding: Self.second, draftName: nil)
        library.unregister(window, from: Self.first)

        #expect(library.holders(of: Self.second) == [window])
    }

    /// Weak only as a safeguard: a window torn down without unregistering holds nothing.
    @Test("a window whose owner is gone holds nothing")
    func aReleasedOwnerHoldsNothing() throws {
        let library = Self.library(InMemoryProjectStore())
        let window = WindowToken()
        do {
            let owner = WindowOwner()
            library.register(window, owner: owner, holding: Self.first, draftName: "Design")
        }

        #expect(library.holders(of: Self.first).isEmpty)
        #expect(try library.uniquedName(Self.name("Design")).value == "Design")
    }

    // MARK: Names (D4)

    @Test("generated names avoid persisted names, refused files' names and live drafts' names")
    func uniquedNamesAvoidEveryKnownName() throws {
        var entries: [ProjectID: InMemoryProjectStore.Entry] = [Self.first: .program(Self.named("Flower"))]
        entries[Self.second] = .refused(.corrupt, name: "Old")
        let store = InMemoryProjectStore(entries)
        let library = Self.library(store)
        let owner = WindowOwner()
        let window = WindowToken()
        library.register(window, owner: owner, holding: .fixed(3), draftName: "Design")

        #expect(try library.uniquedName(Self.name("Flower")).value == "Flower 2")
        #expect(try library.uniquedName(Self.name("old")).value == "old 2")
        #expect(try library.uniquedName(Self.name("Design")).value == "Design 2")
        #expect(try library.uniquedName(Self.name("Moon")).value == "Moon")

        library.unregister(window, from: .fixed(3))
        #expect(try library.uniquedName(Self.name("Design")).value == "Design")
    }

    // MARK: Duplicate (D3)

    @Test("a duplicate is written at once under a new ID with a uniqued name and equal content")
    func duplicate() {
        let store = InMemoryProjectStore([Self.first: .program(Self.named("Flower"))])
        let ids = SequentialProjectIDs()
        let library = Self.library(store, ids: ids)
        let expectedID = SequentialProjectIDs().make()

        let copy = library.duplicate(Self.named("Flower"))

        #expect(copy == expectedID)
        #expect(copy != Self.first)
        #expect(store.program(expectedID) == Self.named("Flower 2"))
        #expect(store.program(Self.first) == Self.named("Flower"))
        #expect(library.files.contains { $0.id == expectedID && $0.inspection == .openable(Self.named("Flower 2")) })
    }

    @Test("a program with no valid name duplicates under the default name")
    func duplicateOfAnUnnamedProgram() {
        let store = InMemoryProjectStore()
        let library = Self.library(store)

        let copy = library.duplicate(Self.named(""))

        #expect(copy.flatMap(store.program)?.name == "Design")
    }

    @Test("a duplicate whose write fails leaves no project behind")
    func aFailedDuplicate() {
        let store = InMemoryProjectStore()
        store.failingSaves = [SequentialProjectIDs().make()]
        let library = Self.library(store)

        #expect(library.duplicate(Self.rosette) == nil)
        #expect(library.files.isEmpty)
    }

    // MARK: Renaming a closed project (D8)

    /// A catalog write, but a real edit: it mints a revision, so a window's save from before the
    /// rename cannot put the old name back.
    @Test("renaming a closed project writes it under a fresh revision and updates its summary")
    func renameAClosedProject() throws {
        let store = InMemoryProjectStore([Self.first: .program(Self.named("Star"))])
        let library = Self.library(store)
        let before = library.mintRevision()
        #expect(library.save(Self.named("Star"), to: Self.first, revision: before) == .written)

        #expect(try library.rename(Self.first, to: Self.name("Moon")) == .written)

        #expect(store.program(Self.first) == Self.named("Moon"))
        #expect(library.files.map(\.inspection) == [.openable(Self.named("Moon"))])
        #expect(library.save(Self.named("Star"), to: Self.first, revision: before) == .superseded)
    }

    @Test("a refused or missing project cannot be renamed, and nothing is written")
    func renameARefusedProject() throws {
        let store = InMemoryProjectStore([Self.first: .refused(.corrupt, name: "Old")])
        let library = Self.library(store)

        #expect(try library.rename(Self.first, to: Self.name("Moon")) == .blocked)
        #expect(try library.rename(Self.second, to: Self.name("Moon")) == .blocked)

        #expect(store.saves.isEmpty)
    }
}
