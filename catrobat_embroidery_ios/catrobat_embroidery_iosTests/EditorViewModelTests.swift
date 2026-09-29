@testable import catrobat_embroidery_ios
import EditorCore
import ProgramModel
import Testing

/// US-405 test-plan items 1 and 2: the editor view model's single `apply` door, in isolation
/// from the app model that listens to it — and US-408's two other doors, undo and redo, and
/// the list gestures that reach `apply` through it.
///
/// Every program assertion compares **whole `Program` values** (ADR-006 pattern 3). The
/// fixture is deliberately not `Program.blank`, so these tests and `BlankProgramTests` fail
/// independently: a wrong blank program must not also make the edit door look broken.
@MainActor
@Suite("EditorViewModel")
struct EditorViewModelTests {
    /// One scene, one object, one empty script — and a name, so the no-op rename below has
    /// something to repeat.
    private static let seed = Program(
        name: "fixture",
        scenes: [Scene(objects: [Object(scripts: [Script()])])]
    )

    /// How many times the editor announced an applied edit. A class so the closure the
    /// editor holds and the test's expectation read one counter.
    private final class Announcements {
        var fired = 0
    }

    private static func editor() -> (EditorViewModel, Announcements) {
        let editor = EditorViewModel(program: seed)
        let announcements = Announcements()
        editor.onProgramChanged = { announcements.fired += 1 }
        return (editor, announcements)
    }

    // MARK: 1 — an applied edit

    @Test("an applied edit updates the whole program, records one entry and announces once")
    func anAppliedEditUpdatesTheProgramAndRecordsOneEntry() {
        let (editor, announcements) = Self.editor()
        var expected = Self.seed
        expected.scenes[0].objects[0].scripts[0].bricks = BrickKind.stitch.template()

        let result = editor.apply(.insert(.stitch, at: BrickAddress(brickIndex: 0)))

        #expect(result == .applied(expected))
        #expect(editor.program == expected)
        #expect(editor.undoStack.undoDepth == 1)
        #expect(editor.undoStack.canUndo)
        #expect(announcements.fired == 1)
    }

    /// Two edits, two entries, two announcements — so an implementation that announced once
    /// per editor rather than once per edit cannot pass the test above by accident.
    @Test("each applied edit announces separately")
    func eachAppliedEditAnnouncesSeparately() {
        let (editor, announcements) = Self.editor()

        editor.apply(.insert(.stitch, at: BrickAddress(brickIndex: 0)))
        editor.apply(.renameProgram("renamed"))

        #expect(editor.program.name == "renamed")
        #expect(editor.undoStack.undoDepth == 2)
        #expect(announcements.fired == 2)
    }

    // MARK: 2 — a rejected edit

    /// The reason ADR-033 made `apply` return a result: a rejected edit must record nothing
    /// and void nothing, and its caller must still be told why.
    @Test("a rejected edit leaves the program identical, records nothing and announces nothing")
    func aRejectedEditChangesNothing() {
        let (editor, announcements) = Self.editor()

        let result = editor.apply(.insert(.loopEnd, at: BrickAddress(brickIndex: 0)))

        #expect(result == .rejected(.cannotInsertLoopEnd))
        #expect(editor.program == Self.seed)
        #expect(editor.undoStack.undoDepth == 0)
        #expect(announcements.fired == 0)
    }

    /// Decided at planning (2026-09-27, ADR-038): an edit that applies but changes nothing
    /// does not void the run. `UndoStack` already records nothing for it; voiding a finished
    /// design over an edit that did not happen would be the same mistake one layer up.
    @Test("an edit that applies but changes nothing does not announce")
    func anUnchangingEditDoesNotAnnounce() {
        let (editor, announcements) = Self.editor()

        let result = editor.apply(.renameProgram(Self.seed.name))

        #expect(result == .applied(Self.seed))
        #expect(editor.program == Self.seed)
        #expect(editor.undoStack.undoDepth == 0)
        #expect(announcements.fired == 0)
    }

    // MARK: Loading

    /// `load` is `UndoStack.reset(to:)`, which clears both directions — so a loaded program
    /// arrives with no history from the one it replaced, and loading announces nothing: it is
    /// not an edit.
    @Test("loading replaces the program, clears the history and announces nothing")
    func loadingReplacesTheProgramAndClearsHistory() {
        let (editor, announcements) = Self.editor()
        editor.apply(.renameProgram("edited"))
        announcements.fired = 0
        let other = Program(name: "other")

        editor.load(other)

        #expect(editor.program == other)
        #expect(!editor.undoStack.canUndo)
        #expect(!editor.undoStack.canRedo)
        #expect(announcements.fired == 0)
    }

    // MARK: Undo and redo (US-408)

    /// A program with a loop, so a delete has several rows to take and the undo has something
    /// structural to restore.
    private static let looped = Program(
        name: "looped",
        scenes: [Scene(objects: [Object(scripts: [Script(bricks: [
            .stitch, .repeatLoop(times: .number(2)), .sewUp, .loopEnd, .stopRunningStitch
        ])])])]
    )

    private static func loopedEditor() -> (EditorViewModel, Announcements) {
        let editor = EditorViewModel(program: looped)
        let announcements = Announcements()
        editor.onProgramChanged = { announcements.fired += 1 }
        return (editor, announcements)
    }

    /// Undo restores a snapshot from outside the `EditAction` vocabulary, so `apply`'s
    /// announcement cannot cover it — and the run, the prepared file and the autosave hang off
    /// that announcement (ADR-038). It must fire here too, once, and record nothing new.
    @Test("undo restores the previous program, announces once and records no new entry")
    func undoRestoresAndAnnounces() throws {
        let (editor, announcements) = Self.loopedEditor()
        editor.apply(.delete(at: BrickAddress(brickIndex: 1)))
        try #require(editor.program != Self.looped)
        #expect(editor.canUndo)
        #expect(!editor.canRedo)
        announcements.fired = 0

        #expect(editor.undo())

        #expect(editor.program == Self.looped)
        #expect(announcements.fired == 1)
        #expect(editor.undoStack.undoDepth == 0, "the undo recorded an entry of its own")
        #expect(editor.undoStack.redoDepth == 1)
        #expect(!editor.canUndo)
        #expect(editor.canRedo)
    }

    @Test("redo reapplies the undone edit, announces once and records no new entry")
    func redoReappliesAndAnnounces() {
        let (editor, announcements) = Self.loopedEditor()
        editor.apply(.delete(at: BrickAddress(brickIndex: 1)))
        let deleted = editor.program
        editor.undo()
        announcements.fired = 0

        #expect(editor.redo())

        #expect(editor.program == deleted)
        #expect(announcements.fired == 1)
        #expect(editor.undoStack.undoDepth == 1)
        #expect(editor.undoStack.redoDepth == 0)
        #expect(editor.canUndo)
        #expect(!editor.canRedo)
    }

    /// A button that is disabled can still be reached by a keyboard or a stale tap; with no
    /// history it must void nothing.
    @Test("undo and redo with no history change nothing and announce nothing")
    func emptyHistoryIsInert() {
        let (editor, announcements) = Self.loopedEditor()

        #expect(!editor.undo())
        #expect(!editor.redo())

        #expect(editor.program == Self.looped)
        #expect(announcements.fired == 0)
    }

    // MARK: The list's gestures (US-408)

    /// ADR-006 pattern 1: the list's `.onMove` reaches the program through `apply`, so it is
    /// recorded and announced like every other edit. Dropping the loop at the end — `.onMove`
    /// says 5, the model 2 — is the conversion, end to end.
    @Test("a drag goes through apply: converted, recorded and announced")
    func aDragGoesThroughApply() {
        let (editor, announcements) = Self.loopedEditor()
        var expected = Self.looped
        expected.scenes[0].objects[0].scripts[0].bricks = [
            .stitch, .stopRunningStitch, .repeatLoop(times: .number(2)), .sewUp, .loopEnd
        ]

        let result = editor.moveRows(fromOffsets: [1], toOffset: 5)

        #expect(result == .applied(expected))
        #expect(editor.program == expected)
        #expect(editor.undoStack.undoDepth == 1)
        #expect(announcements.fired == 1)
    }

    /// Items 4 and 5 at the editor: a drag from a loop end, and a drag of two rows, each leave
    /// the program as it was.
    @Test("a refused drag changes nothing and announces nothing")
    func aRefusedDragChangesNothing() {
        let (editor, announcements) = Self.loopedEditor()

        #expect(editor.moveRows(fromOffsets: [3], toOffset: 0) == .rejected(.cannotMoveLoopEnd(at: BrickAddress(brickIndex: 3))))
        #expect(editor.moveRows(fromOffsets: [0, 4], toOffset: 2) == nil)

        #expect(editor.program == Self.looped)
        #expect(editor.undoStack.undoDepth == 0)
        #expect(announcements.fired == 0)
    }

    @Test("a swipe on a loop end goes through apply and deletes the whole loop")
    func aSwipeGoesThroughApply() {
        let (editor, announcements) = Self.loopedEditor()
        var expected = Self.looped
        expected.scenes[0].objects[0].scripts[0].bricks = [.stitch, .stopRunningStitch]

        #expect(editor.deleteRows(atOffsets: [3]) == .applied(expected))

        #expect(editor.program == expected)
        #expect(editor.undoStack.undoDepth == 1)
        #expect(announcements.fired == 1)
    }

    @Test("a new editor holds the blank program")
    func aNewEditorHoldsTheBlankProgram() {
        #expect(EditorViewModel().program == .blank)
    }
}
