@testable import catrobat_embroidery_ios
import EditorCore
import Foundation
import ProgramModel
import Samples
import Testing

/// The shared guard on the saved program, alone (US-406; ADR-037's multi-window half).
///
/// The revision rule is tested here, against the coordinator, and nowhere in a double: the
/// store holds no policy, so a green here cannot be the double's own copy of the rule passing.
@MainActor
@Suite("Program autosave")
struct ProgramAutosaveTests {
    private static let rosette = SampleLibrary[.octagonRosette].program
    private static let coil = SampleLibrary[.squareCoil].program

    // MARK: Revisions

    @Test("each minted revision is newer than every one before it")
    func revisionsIncrease() {
        let autosave = ProgramAutosave(store: InMemoryProgramStore())

        let first = autosave.mintRevision()
        let second = autosave.mintRevision()
        let third = autosave.mintRevision()

        #expect(first < second)
        #expect(second < third)
    }

    @Test("a save with the newest revision is written")
    func aCurrentSaveIsWritten() {
        let store = InMemoryProgramStore()
        let autosave = ProgramAutosave(store: store)

        let outcome = autosave.save(Self.rosette, revision: autosave.mintRevision())

        #expect(outcome == .written)
        #expect(store.saves == [Self.rosette])
        #expect(autosave.failure == nil)
    }

    /// Test-plan item 10. Different programs, because saving one value twice cannot detect a
    /// reordering; and the *older* request arrives last, which is the case an ordered queue
    /// alone does not stop.
    @Test("a save older than one already accepted is dropped, whatever order they arrive in")
    func anOlderSaveArrivingLastIsDropped() {
        let store = InMemoryProgramStore()
        let autosave = ProgramAutosave(store: store)
        let older = autosave.mintRevision()
        let newer = autosave.mintRevision()

        let first = autosave.save(Self.coil, revision: newer)
        let second = autosave.save(Self.rosette, revision: older)

        #expect(first == .written)
        #expect(second == .superseded)
        #expect(store.stored == Self.coil)
        #expect(store.saves == [Self.coil])
    }

    /// An equal revision is the same edit asking again — a lifecycle save retrying a write that
    /// failed — and must not be dropped as stale.
    @Test("a save repeating the accepted revision is written again")
    func anEqualRevisionIsRewritten() {
        let store = InMemoryProgramStore()
        let autosave = ProgramAutosave(store: store)
        let revision = autosave.mintRevision()

        autosave.save(Self.rosette, revision: revision)
        let again = autosave.save(Self.rosette, revision: revision)

        #expect(again == .written)
        #expect(store.saves == [Self.rosette, Self.rosette])
    }

    // MARK: Failure — test-plan item 7

    @Test("a throwing save is surfaced, not swallowed")
    func aThrowingSaveIsSurfaced() {
        let store = InMemoryProgramStore()
        store.failsSaves = true
        let autosave = ProgramAutosave(store: store)

        let outcome = autosave.save(Self.rosette, revision: autosave.mintRevision())

        #expect(outcome == .failed)
        #expect(autosave.failure == .saveFailed)
    }

    /// The failure is a state, not an event: it holds until a write works, and then clears.
    @Test("the next successful write clears the failure, even at the failed revision")
    func theNextSuccessfulWriteClearsTheFailure() {
        let store = InMemoryProgramStore()
        store.failsSaves = true
        let autosave = ProgramAutosave(store: store)
        let revision = autosave.mintRevision()
        autosave.save(Self.rosette, revision: revision)

        store.failsSaves = false
        let retry = autosave.save(Self.rosette, revision: revision)

        #expect(retry == .written)
        #expect(autosave.failure == nil)
        #expect(store.stored == Self.rosette)
    }

    // MARK: Restore

    @Test("restore with nothing saved reports nothing saved and writes nothing")
    func restoreWithNothingSaved() {
        let store = InMemoryProgramStore()
        let autosave = ProgramAutosave(store: store)

        #expect(autosave.restore() == .nothingSaved)
        #expect(store.saves.isEmpty)
        #expect(store.setAsideCount == 0)
    }

    @Test("restore returns the saved program and writes nothing back")
    func restoreReturnsTheSavedProgram() {
        let store = InMemoryProgramStore(stored: Self.rosette)
        let autosave = ProgramAutosave(store: store)

        #expect(autosave.restore() == .restored(Self.rosette))
        #expect(store.saves.isEmpty)
        #expect(store.setAsideCount == 0)
    }

    @Test("restore sets a refused file aside and reports the reason and that it was preserved")
    func restoreSetsARefusedFileAside() {
        let store = InMemoryProgramStore()
        store.loadError = .document(.unsupportedVersion(2))
        let autosave = ProgramAutosave(store: store)

        let restore = autosave.restore()

        #expect(restore == .refused(ProgramRefusal(reason: .document(.unsupportedVersion(2)), preserved: true)))
        #expect(store.setAsideCount == 1)
        #expect(store.saves.isEmpty)
        #expect(autosave.failure == nil)
    }

    // MARK: A refused file that could not be preserved — test-plan item 11's coordinator half

    @Test("while a refused file could not be set aside, every save is blocked and says why")
    func anUnpreservedFileBlocksEverySave() throws {
        try inDisposableDirectory { directory in
            let disk = DocumentsProgramStore(directory: directory)
            try RefusedDocument.corrupt.write(to: disk.workingURL)
            let autosave = ProgramAutosave(store: SetAsideFailingStore(wrapping: disk))

            let restore = autosave.restore()
            let outcome = autosave.save(Self.rosette, revision: autosave.mintRevision())

            #expect(restore == .refused(ProgramRefusal(reason: .document(.corrupt), preserved: false)))
            #expect(outcome == .blocked)
            #expect(autosave.failure == .unpreservedDocument)
            #expect(try Data(contentsOf: disk.workingURL) == RefusedDocument.corrupt)
        }
    }

    /// The block is lifted by the thing it waits for, and only by that: a later restore — a new
    /// window, or the next launch — that does manage to move the file.
    @Test("a later restore that sets the file aside lifts the block")
    func aLaterSuccessfulSetAsideLiftsTheBlock() throws {
        try inDisposableDirectory { directory in
            let disk = DocumentsProgramStore(directory: directory)
            try RefusedDocument.corrupt.write(to: disk.workingURL)
            let switchable = SetAsideFailingStore(wrapping: disk)
            let autosave = ProgramAutosave(store: switchable)
            _ = autosave.restore()
            try #require(autosave.failure == .unpreservedDocument)

            switchable.setAsideFails = false
            let second = autosave.restore()
            let outcome = autosave.save(Self.rosette, revision: autosave.mintRevision())

            #expect(second == .refused(ProgramRefusal(reason: .document(.corrupt), preserved: true)))
            #expect(outcome == .written)
            #expect(autosave.failure == nil)
            #expect(try disk.load() == Self.rosette)
            #expect(try setAsideFiles(in: directory) == [RefusedDocument.corrupt])
        }
    }
}
