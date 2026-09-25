import EditorCore
import ProgramModel
import Testing

/// US-403 at the 50-entry bound: how coalescing sessions interact with
/// eviction, and the sealing rule that bounds what an entry may retain
/// (ADR-036). Split from `UndoCoalescingTests` when the review rounds grew it
/// past SwiftLint's length limits; the rule under test is the same one stated
/// there.
@Suite("UndoStack — sessions at the bound")
struct UndoEvictionTests {
    typealias Fixtures = EditorCoreFixtures

    // MARK: The bound under a session

    /// At capacity, folded edits must neither grow the stack nor evict: the
    /// oldest surviving entry is still reachable at the bottom.
    @Test("folding at capacity neither grows the stack nor evicts")
    func foldingAtCapacityDoesNotEvict() {
        var stack = UndoStack(program: Fixtures.undoSeed)
        for index in 1 ... 49 {
            stack.apply(.renameProgram("p\(index)"))
        }
        let key = stack.beginEdit(of: Fixtures.stepperAddress)
        for value in 1 ... 5 {
            stack.apply(Fixtures.step(to: Double(value)), coalescing: key)
        }
        #expect(stack.undoDepth == UndoStack.capacity)

        var last: Program?
        while let program = stack.undo() {
            last = program
        }
        #expect(last == Fixtures.undoSeed)
    }

    /// Codex round 1: the session's first push happens **at** capacity, so it
    /// evicts the seed; the session then nets to zero and its entry is dropped.
    /// Dropping it must also give back what its push evicted, or a session that
    /// changed nothing has still cost the user their oldest undo step.
    @Test("a net-zero session at capacity restores the entry its push evicted")
    func netZeroSessionAtCapacityRestoresTheEvictedEntry() throws {
        var stack = UndoStack(program: Fixtures.undoSeed)
        for index in 1 ... 50 {
            stack.apply(.renameProgram("p\(index)"))
        }
        try #require(stack.undoDepth == UndoStack.capacity)
        let before = stack

        let key = stack.beginEdit(of: Fixtures.stepperAddress)
        stack.apply(Fixtures.step(to: 11), coalescing: key)
        stack.apply(Fixtures.step(to: 10), coalescing: key)
        stack.endEdit(key)

        #expect(stack.current == Fixtures.named("p50"))
        #expect(stack.undoDepth == UndoStack.capacity)

        // The whole stack is back where it was — the restored entry sealed —
        // bar the serial the session consumed. Walking program values alone
        // could not see a restored entry carrying the session's key (Codex
        // round 4).
        var reference = before
        _ = reference.beginEdit(of: Fixtures.stepperAddress)
        reference.abandonEdit()
        #expect(stack == reference)

        var last: Program?
        while let program = stack.undo() {
            last = program
        }
        #expect(last == Fixtures.undoSeed)

        // And a session at capacity that does *not* net to zero still evicts:
        // the seed is gone, exactly as for an un-keyed edit.
        var kept = before
        let other = kept.beginEdit(of: Fixtures.stepperAddress)
        kept.apply(Fixtures.step(to: 11), coalescing: other)
        kept.apply(Fixtures.step(to: 12), coalescing: other)
        #expect(kept.undoDepth == UndoStack.capacity)
        var bottom: Program?
        while let program = kept.undo() {
            bottom = program
        }
        #expect(bottom == Fixtures.named("p1"))
    }

    // MARK: An entry that can no longer fold is sealed

    /// Codex round 2: a keyed entry pushed at capacity held its evicted
    /// snapshot after its session closed — invisible in the history, but a
    /// retained graph nothing could ever restore. Once an entry can no longer
    /// fold it is sealed, so the stack equals one that recorded the same edit
    /// un-keyed (same serial consumed, same session state).
    enum Closure: CaseIterable, Sendable {
        case endEdit, abandonEdit, supersede, staleKey, coveredThenClosed
    }

    @Test("an entry that can no longer fold holds no key and no eviction", arguments: Closure.allCases)
    func closedEntryIsSealed(closure: Closure) throws {
        var full = UndoStack(program: Fixtures.undoSeed)
        for index in 1 ... 50 {
            full.apply(.renameProgram("p\(index)"))
        }
        try #require(full.undoDepth == UndoStack.capacity)

        var keyed = full
        var unkeyed = full
        let key = keyed.beginEdit(of: Fixtures.stepperAddress)
        _ = unkeyed.beginEdit(of: Fixtures.stepperAddress)
        unkeyed.abandonEdit()

        switch closure {
        case .endEdit:
            keyed.apply(Fixtures.step(to: 1), coalescing: key)
            keyed.endEdit(key)
            unkeyed.apply(Fixtures.step(to: 1))
        case .abandonEdit:
            keyed.apply(Fixtures.step(to: 1), coalescing: key)
            keyed.abandonEdit()
            unkeyed.apply(Fixtures.step(to: 1))
        case .supersede:
            keyed.apply(Fixtures.step(to: 1), coalescing: key)
            _ = keyed.beginEdit(of: Fixtures.stepperAddress)
            unkeyed.apply(Fixtures.step(to: 1))
            _ = unkeyed.beginEdit(of: Fixtures.stepperAddress)
        case .staleKey:
            keyed.endEdit(key)
            keyed.apply(Fixtures.step(to: 1), coalescing: key)
            unkeyed.apply(Fixtures.step(to: 1))
        case .coveredThenClosed:
            // The keyed entry holds an eviction when an un-keyed edit covers
            // it: covering must drop the eviction as well as the key, or the
            // buried entry keeps a snapshot nothing can restore (Codex round 4).
            keyed.apply(Fixtures.step(to: 1), coalescing: key)
            keyed.apply(.renameProgram("x"))
            keyed.endEdit(key)
            unkeyed.apply(Fixtures.step(to: 1))
            unkeyed.apply(.renameProgram("x"))
        }
        #expect(keyed == unkeyed)
    }

    /// Codex round 3: sealing only the top entry on close left a session's
    /// **buried** keyed entries — separated by un-keyed edits — carrying the
    /// dead key. A covered entry can never fold again, so it is sealed when it
    /// is covered, and the invariant becomes: only the top entry can carry a
    /// key or an eviction.
    @Test("a closed session's buried entries are sealed too")
    func buriedEntriesAreSealed() {
        var keyed = UndoStack(program: Fixtures.undoSeed)
        var unkeyed = keyed
        let key = keyed.beginEdit(of: Fixtures.stepperAddress)
        _ = unkeyed.beginEdit(of: Fixtures.stepperAddress)
        unkeyed.abandonEdit()

        keyed.apply(Fixtures.step(to: 1), coalescing: key)
        keyed.apply(.renameProgram("x"))
        keyed.apply(Fixtures.step(to: 2), coalescing: key)
        keyed.apply(.renameProgram("y"))
        keyed.endEdit(key)

        unkeyed.apply(Fixtures.step(to: 1))
        unkeyed.apply(.renameProgram("x"))
        unkeyed.apply(Fixtures.step(to: 2))
        unkeyed.apply(.renameProgram("y"))

        #expect(keyed == unkeyed)
    }
}
