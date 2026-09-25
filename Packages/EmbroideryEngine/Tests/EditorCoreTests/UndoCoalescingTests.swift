import EditorCore
import ProgramModel
import Testing

/// US-403's coalescing half: an explicit session, never a timer (test-plan
/// items 4–7, plus the session-lifecycle hazards the plan review found).
///
/// The rule under test (ADR-036): an applied edit coalesces into the top entry
/// **iff** its key is non-`nil`, is the currently open session's key, and is the
/// key the top entry was recorded under. Anything else pushes.
///
/// The edits are stepper-shaped — `replaceBrick` on one `moveNSteps` with a
/// fresh value each time — because that is the US-410 session this exists for,
/// and every value is distinct, so "undo returned the state before the first of
/// the twenty" cannot be satisfied by the state before the second.
@Suite("UndoStack — coalescing sessions")
struct UndoCoalescingTests {
    typealias Fixtures = EditorCoreFixtures

    // MARK: 4 — one session, one step

    /// A key-less edit sits *below* the session, so the test can tell "undid the
    /// session" (lands on `pre`) from "undid everything" (lands on the seed) and
    /// from "undid one keystroke" (lands on step 19).
    @Test("twenty edits under one key are one undo step back to before the first")
    func oneKeyIsOneStep() {
        var stack = UndoStack(program: Fixtures.undoSeed)
        stack.apply(.renameProgram("pre"))

        let key = stack.beginEdit(of: Fixtures.stepperAddress)
        for value in 1 ... 20 {
            stack.apply(Fixtures.step(to: Double(value)), coalescing: key)
        }
        stack.endEdit(key)

        #expect(stack.current == Fixtures.stepped(to: 20, name: "pre"))
        #expect(stack.undoDepth == 2)

        #expect(stack.undo() == Fixtures.named("pre"))
        #expect(stack.canUndo)
        #expect(stack.undo() == Fixtures.undoSeed)
        #expect(!stack.canUndo)
    }

    // MARK: 5 — twenty keys, twenty steps

    @Test("twenty edits under twenty sessions are twenty steps, walked in order")
    func twentyKeysAreTwentySteps() {
        var stack = UndoStack(program: Fixtures.undoSeed)
        var keys: [CoalescingKey] = []
        for value in 1 ... 20 {
            let key = stack.beginEdit(of: Fixtures.stepperAddress)
            keys.append(key)
            stack.apply(Fixtures.step(to: Double(value)), coalescing: key)
            stack.endEdit(key)
        }
        #expect(Set(keys).count == 20, "every session mints a distinct key")
        #expect(stack.undoDepth == 20)

        var reached: [Program] = []
        while let program = stack.undo() {
            reached.append(program)
        }
        #expect(reached == (1 ... 19).reversed().map { Fixtures.stepped(to: Double($0)) } + [Fixtures.undoSeed])
    }

    // MARK: 6 — a nil key always pushes

    @Test("a nil-keyed edit pushes even straight after a keyed one, and splits the session")
    func nilKeyAlwaysPushes() {
        var stack = UndoStack(program: Fixtures.undoSeed)
        let key = stack.beginEdit(of: Fixtures.stepperAddress)
        stack.apply(Fixtures.step(to: 1), coalescing: key)
        stack.apply(.renameProgram("x"))
        stack.apply(.renameProgram("y"))
        #expect(stack.undoDepth == 3)

        // The session is still open, but the top entry is the nil-keyed one, so
        // the next keyed edit cannot fold into it.
        #expect(stack.openSession == key)
        stack.apply(Fixtures.step(to: 2), coalescing: key)
        #expect(stack.undoDepth == 4)

        #expect(stack.undo() == Fixtures.stepped(to: 1, name: "y"))
        #expect(stack.undo() == Fixtures.stepped(to: 1, name: "x"))
        #expect(stack.undo() == Fixtures.stepped(to: 1))
        #expect(stack.undo() == Fixtures.undoSeed)
    }

    // MARK: 7 — endEdit is idempotent, and a closed key never coalesces

    /// Re-uses the **same** closed key for the next edit: a fresh `beginEdit`
    /// would push trivially and prove nothing about the closed session.
    @Test("endEdit twice equals once; an edit under the closed key pushes")
    func endEditIsIdempotent() {
        var stack = UndoStack(program: Fixtures.undoSeed)
        let key = stack.beginEdit(of: Fixtures.stepperAddress)
        stack.apply(Fixtures.step(to: 1), coalescing: key)
        stack.endEdit(key)

        var twice = stack
        twice.endEdit(key)
        #expect(twice == stack)

        stack.apply(Fixtures.step(to: 2), coalescing: key)
        #expect(stack.undoDepth == 2)
        #expect(stack.undo() == Fixtures.stepped(to: 1))
    }

    // MARK: The ADR-023 container swap

    /// Sheet B's `onAppear` can run before sheet A's `onDisappear` when a
    /// size-class change swaps the container. A key-less `endEdit()` arriving
    /// late from A would close **B's** session; `endEdit(_:)` only closes the
    /// session whose key it is given.
    @Test("a late endEdit from a superseded session does not close the open one")
    func lateEndEditLeavesTheNewSessionOpen() {
        var stack = UndoStack(program: Fixtures.undoSeed)
        let sheetA = stack.beginEdit(of: Fixtures.stepperAddress)
        let sheetB = stack.beginEdit(of: Fixtures.stepperAddress)
        #expect(sheetA != sheetB)

        stack.endEdit(sheetA)
        stack.apply(Fixtures.step(to: 1), coalescing: sheetB)
        stack.apply(Fixtures.step(to: 2), coalescing: sheetB)

        #expect(stack.undoDepth == 1)
        #expect(stack.undo() == Fixtures.undoSeed)
    }

    /// `beginEdit` supersedes: the superseded key is no longer the open one, so
    /// an edit under it pushes rather than folding into its old entry.
    @Test("a superseded key never coalesces")
    func supersededKeyNeverCoalesces() {
        var stack = UndoStack(program: Fixtures.undoSeed)
        let sheetA = stack.beginEdit(of: Fixtures.stepperAddress)
        stack.apply(Fixtures.step(to: 1), coalescing: sheetA)
        let sheetB = stack.beginEdit(of: Fixtures.stepperAddress)

        stack.apply(Fixtures.step(to: 2), coalescing: sheetA)
        #expect(stack.undoDepth == 2)

        // …and a late keystroke from A must not close B's session either: B's
        // edits still fold — one entry for B, not two.
        #expect(stack.openSession == sheetB)
        stack.apply(Fixtures.step(to: 3), coalescing: sheetB)
        stack.apply(Fixtures.step(to: 4), coalescing: sheetB)
        #expect(stack.undoDepth == 3)
        #expect(stack.undo() == Fixtures.stepped(to: 2))
    }

    /// The view model's teardown path, where no key is at hand: the acceptance
    /// criterion's "clear a session without ending a well-formed one".
    @Test("abandonEdit clears the open session, idempotently")
    func abandonEditClearsTheSession() {
        var stack = UndoStack(program: Fixtures.undoSeed)
        let key = stack.beginEdit(of: Fixtures.stepperAddress)
        stack.apply(Fixtures.step(to: 1), coalescing: key)
        stack.abandonEdit()

        var twice = stack
        twice.abandonEdit()
        #expect(twice == stack)

        stack.apply(Fixtures.step(to: 2), coalescing: key)
        #expect(stack.undoDepth == 2)
        #expect(stack.undo() == Fixtures.stepped(to: 1))
    }

    // MARK: History transitions are coalescing boundaries

    /// Walk-through from the plan review: after an undo the top entry is no
    /// longer the session's, so the next keyed edit starts a new entry — and
    /// clears redo, like any edit.
    @Test("session, undo, edit under the same key — a new entry, redo cleared")
    func undoInsideASessionStartsANewEntry() {
        var stack = UndoStack(program: Fixtures.undoSeed)
        let key = stack.beginEdit(of: Fixtures.stepperAddress)
        for value in 1 ... 3 {
            stack.apply(Fixtures.step(to: Double(value)), coalescing: key)
        }
        #expect(stack.undo() == Fixtures.undoSeed)
        // Undo is a boundary, not a dismissal: the sheet is still up, so the
        // session stays open and later keystrokes still coalesce.
        #expect(stack.openSession == key)

        stack.apply(Fixtures.step(to: 4), coalescing: key)
        stack.apply(Fixtures.step(to: 5), coalescing: key)
        #expect(stack.current == Fixtures.stepped(to: 5))
        #expect(stack.undoDepth == 1)
        #expect(!stack.canRedo)
        #expect(stack.undo() == Fixtures.undoSeed)
    }

    /// The case the first version got wrong (swift-code-reviewer): with
    /// `[K, nil, K]` on the stack, two undos expose the *first* K entry while K
    /// is still open, and the next keystroke folded into it — so "a history
    /// transition is a coalescing boundary" was false. Undo now seals the entry
    /// it exposes.
    @Test("undo seals the entry it exposes, even one recorded under the open key")
    func undoSealsTheExposedEntry() {
        var stack = UndoStack(program: Fixtures.undoSeed)
        let key = stack.beginEdit(of: Fixtures.stepperAddress)
        stack.apply(Fixtures.step(to: 1), coalescing: key)
        stack.apply(.renameProgram("x"))
        stack.apply(Fixtures.step(to: 2), coalescing: key)
        #expect(stack.undo() == Fixtures.stepped(to: 1, name: "x"))
        #expect(stack.undo() == Fixtures.stepped(to: 1))

        stack.apply(Fixtures.step(to: 3), coalescing: key)
        #expect(stack.undoDepth == 2)
        #expect(stack.undo() == Fixtures.stepped(to: 1))
        #expect(stack.undo() == Fixtures.undoSeed)
    }

    /// A redone entry comes back **sealed**: folding a later keystroke into it
    /// would silently change what the redo restored.
    @Test("an entry restored by redo is sealed against its old key")
    func redoSealsTheEntry() {
        var stack = UndoStack(program: Fixtures.undoSeed)
        let key = stack.beginEdit(of: Fixtures.stepperAddress)
        stack.apply(Fixtures.step(to: 1), coalescing: key)
        stack.undo()
        #expect(stack.redo() == Fixtures.stepped(to: 1))
        #expect(stack.openSession == key)

        stack.apply(Fixtures.step(to: 2), coalescing: key)
        #expect(stack.undoDepth == 2)
        #expect(stack.undo() == Fixtures.stepped(to: 1))
    }

    // MARK: A session that returns to where it started

    /// Stepper 10 → 11 → 10: every edit changes `current`, so the no-op guard
    /// passes each time, yet the session as a whole changed nothing. Its entry
    /// is dropped at the fold that makes it a no-op, rather than left as an undo
    /// tap that visibly does nothing (ADR-036).
    @Test("a session that nets to zero leaves no entry, and stays open")
    func netZeroSessionLeavesNoEntry() {
        var stack = UndoStack(program: Fixtures.undoSeed)
        stack.apply(.renameProgram("pre"))
        let key = stack.beginEdit(of: Fixtures.stepperAddress)

        stack.apply(Fixtures.step(to: 11), coalescing: key)
        stack.apply(Fixtures.step(to: 10), coalescing: key)
        #expect(stack.current == Fixtures.named("pre"))
        #expect(stack.undoDepth == 1)
        #expect(stack.openSession == key)

        // Carrying on in the same session records afresh from here.
        stack.apply(Fixtures.step(to: 12), coalescing: key)
        stack.apply(Fixtures.step(to: 13), coalescing: key)
        #expect(stack.undoDepth == 2)
        #expect(stack.undo() == Fixtures.named("pre"))
        #expect(stack.undo() == Fixtures.undoSeed)
    }

    // MARK: Rejection inside a session

    /// A rejected keystroke during a live session records nothing — including
    /// not closing the session (Codex round 1).
    @Test("a rejected edit inside a session leaves the whole stack unchanged")
    func rejectionInsideASessionChangesNothing() {
        var stack = UndoStack(program: Fixtures.undoSeed)
        let key = stack.beginEdit(of: Fixtures.stepperAddress)
        stack.apply(Fixtures.step(to: 1), coalescing: key)
        let before = stack

        let result = stack.apply(
            .replaceBrick(at: Fixtures.stepperAddress, with: .sewUp),
            coalescing: key
        )
        #expect(result == .rejected(.cannotChangeBrickKind(from: .moveNSteps, to: .sewUp)))
        #expect(stack == before)
    }

    // MARK: Reset keeps minting fresh keys

    /// If `reset` restarted the serial, a key from before the reset would equal
    /// the first key minted after it and coalesce into an unrelated session.
    @Test("keys minted after a reset never equal keys from before it")
    func resetKeepsTheSerialRunning() {
        var stack = UndoStack(program: Fixtures.undoSeed)
        let stale = stack.beginEdit(of: Fixtures.stepperAddress)
        stack.apply(Fixtures.step(to: 1), coalescing: stale)

        stack.reset(to: Fixtures.named("loaded"))
        let fresh = stack.beginEdit(of: Fixtures.stepperAddress)
        #expect(stale != fresh)

        stack.apply(Fixtures.step(to: 2), coalescing: fresh)
        stack.apply(Fixtures.step(to: 3), coalescing: stale)
        #expect(stack.undoDepth == 2)
    }

    /// `reset` also closes the open session: a sheet still presented across a
    /// whole-program replacement must not fold its next edit into the new
    /// program's first entry.
    @Test("reset closes the open session")
    func resetClosesTheSession() {
        var stack = UndoStack(program: Fixtures.undoSeed)
        let key = stack.beginEdit(of: Fixtures.stepperAddress)
        stack.reset(to: Fixtures.named("loaded"))

        stack.apply(Fixtures.step(to: 1), coalescing: key)
        stack.apply(Fixtures.step(to: 2), coalescing: key)
        #expect(stack.undoDepth == 2)
    }
}
