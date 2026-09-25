import EditorCore
import ProgramModel
import Testing

/// US-403's history half: snapshot-before undo, redo, the structural bound,
/// rejection, reset and totality (test-plan items 1–3 and 8–10).
///
/// Every assertion compares **whole `Program` values** (ADR-006 pattern 3), and
/// every program a test walks through is pairwise distinct — built from renames,
/// which never reject — so a stack that pops the wrong snapshot lands on a value
/// that differs rather than on a look-alike.
@Suite("UndoStack — history")
struct UndoStackTests {
    typealias Fixtures = EditorCoreFixtures

    /// A stack that has applied `.renameProgram("p1")` … `"p\(count)"` to the
    /// seed, one un-keyed edit each.
    private static func stack(afterRenames count: Int) -> UndoStack {
        var stack = UndoStack(program: Fixtures.undoSeed)
        for index in stride(from: 1, through: count, by: 1) {
            stack.apply(.renameProgram("p\(index)"))
        }
        return stack
    }

    // MARK: 1 — undo and redo walk the snapshots

    @Test("three edits, undo twice, redo once — the whole program at each step")
    func undoAndRedoWalkTheSnapshots() throws {
        let programs = (0 ... 3).map { Fixtures.named("p\($0)") }
        try #require(Set(programs.map(\.name)).count == 4, "the four programs must be distinct")

        var stack = Self.stack(afterRenames: 3)
        #expect(stack.current == programs[3])

        #expect(stack.undo() == programs[2])
        #expect(stack.current == programs[2])

        #expect(stack.undo() == programs[1])
        #expect(stack.current == programs[1])

        #expect(stack.redo() == programs[2])
        #expect(stack.current == programs[2])

        // One step left in each direction — not zero, not two.
        #expect(stack.undoDepth == 2)
        #expect(stack.redoDepth == 1)

        // The entry redo pushed must restore what redo replaced: undo straight
        // after a redo lands back on p1, and the whole history still walks down
        // to the seed and back up to p3 (swift-code-reviewer: a redo that pushed
        // its *own* result survived every assertion above).
        #expect(stack.undo() == programs[1])
        #expect(stack.undo() == programs[0])
        #expect(stack.undo() == nil)
        #expect(stack.redo() == programs[1])
        #expect(stack.redo() == programs[2])
        #expect(stack.redo() == programs[3])
        #expect(stack.redo() == nil)
    }

    // MARK: 2 — the bound is structural, and it evicts the *oldest*

    /// "Depth is 50" alone also passes a stack that drops the **newest** entry
    /// on overflow, so the test walks the whole remaining history: the first undo
    /// must reach the 59th program and the fiftieth the tenth, and the
    /// fifty-first must find nothing.
    @Test("60 edits against a bound of 50 keep the newest 50")
    func boundEvictsTheOldest() {
        #expect(UndoStack.capacity == 50)

        var stack = Self.stack(afterRenames: 60)
        #expect(stack.undoDepth == 50)
        #expect(stack.canUndo)

        var reached: [String] = []
        while let program = stack.undo() {
            reached.append(program.name)
        }
        #expect(reached == (10 ... 59).reversed().map { "p\($0)" })
        #expect(stack.current == Fixtures.named("p10"))
        #expect(!stack.canUndo)
    }

    // MARK: 3 — a new edit invalidates redo

    @Test("undo twice, edit — redo is gone and undo resumes from the new edit")
    func newEditInvalidatesRedo() throws {
        var stack = Self.stack(afterRenames: 3)
        stack.undo()
        stack.undo()
        try #require(stack.redoDepth == 2)

        stack.apply(.renameProgram("p4"))
        #expect(!stack.canRedo)
        #expect(stack.redoDepth == 0)
        #expect(stack.redo() == nil)
        #expect(stack.current == Fixtures.named("p4"))

        // The discarded branch (p2, p3) is unreachable; undo goes back to p1.
        #expect(stack.undo() == Fixtures.named("p1"))
    }

    // MARK: 8 — a rejected edit records nothing

    /// The reason ADR-033 made `apply` return a result instead of throwing. The
    /// stack starts with **both** directions non-empty, and the whole stack value
    /// is compared, so a rejection that pushed an entry *or* that cleared redo is
    /// red — "depth unchanged" alone would miss the second.
    @Test("a rejected action changes nothing, redo included")
    func rejectionRecordsNothing() throws {
        var stack = Self.stack(afterRenames: 2)
        stack.undo()
        try #require(stack.canUndo && stack.canRedo)
        let before = stack

        let outOfBounds = BrickAddress(brickIndex: 99)
        let result = stack.apply(.delete(at: outOfBounds))

        #expect(result == .rejected(.addressOutOfBounds(.brick, at: outOfBounds)))
        #expect(stack == before)
    }

    // MARK: 9 — reset clears both directions

    @Test("reset replaces the program and clears undo and redo")
    func resetClearsBothDirections() throws {
        var stack = Self.stack(afterRenames: 3)
        stack.undo()
        try #require(stack.canUndo && stack.canRedo)

        let replacement = Fixtures.named("loaded")
        stack.reset(to: replacement)

        #expect(stack.current == replacement)
        #expect(!stack.canUndo)
        #expect(!stack.canRedo)
        #expect(stack.undo() == nil)
        #expect(stack.redo() == nil)
        #expect(stack.current == replacement)
    }

    // MARK: 10 — totality

    @Test("an empty stack's undo and redo return nil and change nothing")
    func emptyStackIsTotal() {
        var stack = UndoStack(program: Fixtures.undoSeed)
        let before = stack

        #expect(stack.undo() == nil)
        #expect(stack.redo() == nil)
        #expect(stack == before)
        #expect(stack.current == Fixtures.undoSeed)
        #expect(!stack.canUndo)
        #expect(!stack.canRedo)
    }

    // MARK: No-op edits

    /// `apply` can return the program unchanged — a rename to the current name,
    /// an identical `replaceBrick`, a leaf moved to its own index. Pushing that
    /// would be an undo tap that visibly does nothing, and clearing redo for it
    /// would destroy history over an edit that did not happen (ADR-036).
    @Test("an applied edit that changes nothing records nothing and keeps redo")
    func noOpRecordsNothing() throws {
        var stack = Self.stack(afterRenames: 2)
        stack.undo()
        try #require(stack.current == Fixtures.named("p1") && stack.canRedo)
        let before = stack

        let result = stack.apply(.renameProgram("p1"))

        #expect(result == .applied(Fixtures.named("p1")))
        #expect(stack == before)
    }

    // MARK: Sendable

    @Test("the stack and its key are Sendable values")
    func stackIsSendable() {
        func requireSendable(_: (some Sendable).Type) {}
        requireSendable(UndoStack.self)
        requireSendable(CoalescingKey.self)
    }
}
