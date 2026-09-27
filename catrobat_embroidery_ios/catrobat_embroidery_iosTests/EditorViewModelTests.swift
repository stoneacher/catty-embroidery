@testable import catrobat_embroidery_ios
import EditorCore
import ProgramModel
import Testing

/// US-405 test-plan items 1 and 2: the editor view model's single `apply` door, in isolation
/// from the app model that listens to it.
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
        editor.onEditApplied = { announcements.fired += 1 }
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

    @Test("a new editor holds the blank program")
    func aNewEditorHoldsTheBlankProgram() {
        #expect(EditorViewModel().program == .blank)
    }
}
