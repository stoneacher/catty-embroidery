# US-403 — Bounded, coalesced undo/redo stack

**Epic**: E5 Block editor | **Estimate**: ~4 h | **Depends on**: US-402

**Story**: As a user, I want to undo anything I do to my program — and I want twenty taps on a stepper to be one undo, not twenty — so experimenting is cheap and a mistake is never expensive.

**This is better than both references, and there is nothing to port.** Catroid has exactly **one** level of undo, stored as a whole-project `undo_code.xml` file, with **no redo**; drag-reorder, brick-add and copy are not undoable at all (`ScriptFragment.java:882-943`). Catty's script editor has **no undo whatsoever** — `NSUndoManager` appears only in PocketPaint. So this is our design, judged against ADR-006 rather than against a reference.

## Why snapshots, and why they are affordable

ADR-006 already chose "bounded in-memory snapshot stack (value semantics make it nearly free)". The measured basis: the two shipped samples are **10 and 15 bricks, ~4 KB** of JSON each, one scene / one object / one script. `Program` is a value type with COW at every array level, and `Brick`/`Formula` being `indirect` means each payload is a heap box that a copy **retains rather than deep-copies**. So a snapshot of an unmutated program is O(1) plus a few retains; after one edit exactly one `[Brick]` buffer is copied. A 200-brick program at 50 deep is on the order of tens of kilobytes.

That reasoning is **not** asserted as a timing or memory bound. US-309 is the precedent: CI refuted a locally derived bound (9.62× on the runner against 3.71× locally) on unmutated code. The bound this story asserts is **structural**.

## Acceptance criteria

- [ ] `UndoStack` lives in `EditorCore` — pure, `Sendable`, no Foundation, on the fast gate.
- [ ] It is **snapshot-before**: it holds the program as it was *before* each edit, plus the current one. This is what makes coalescing expressible and undo a pop rather than an index dance.
- [ ] **Bounded at 50 entries, and the bound is exercised**: after 60 pushes the depth is 50, the oldest snapshot is gone, and `canUndo` is still true. A bound that is never exercised is not a bound.
- [ ] **Redo exists** and is invalidated by a new edit: undo twice, edit, and `canRedo` is false.
- [ ] **Coalescing is an explicit session, never a timer.** `record(before:key:)` takes an optional `CoalescingKey`; a non-`nil` key matching the top of the stack **skips** the record, because the "before" already on the stack is the right one. Sessions are opened and closed by the caller (`beginEdit(of:)` / `endEdit()`), so there is **no clock anywhere** and the whole thing is a pure value.
- [ ] **`endEdit()` is idempotent**, and the stack exposes a way to clear a session without ending a well-formed one. ADR-023's container swap tears down a presented sheet on a size-class change, so `endEdit()` may never fire — and a stale session key would silently swallow the *next*, unrelated edit's undo entry. That is the failure mode this criterion exists to prevent.
- [ ] A **rejected** `EditResult` records nothing. Asserted, because it is the reason ADR-033 made `apply` return a result instead of throwing.
- [ ] `reset()` clears both directions, for the whole-program replacements US-405 introduces (pick a sample, load from disk, new program).

## Test-first plan

1. Push three edits, undo twice, redo once — the resulting `Program` equals the expected whole value at each step.
2. Depth after 60 pushes against a bound of 50 is 50; the program 60 edits ago is unreachable; `canUndo` is true.
3. Redo is invalidated by a new edit after an undo.
4. Twenty records under **one** coalescing key produce **one** undoable step, and undoing it returns the program to its state before the first of the twenty.
5. Twenty records under twenty **different** keys produce twenty steps.
6. A record with a `nil` key always pushes, even immediately after a keyed one.
7. `endEdit()` called twice is the same as once; a record after a closed session pushes a new entry rather than coalescing into the closed one.
8. `.rejected` records nothing: depth is unchanged and `canUndo` is unchanged.
9. `reset()` leaves `canUndo` and `canRedo` both false.
10. An empty stack's `undo()` returns `nil` rather than trapping — the totality test.

**Mutation targets**: off-by-one in the bound (49/51 both pass several of the tests above); coalescing that *replaces* the top snapshot instead of skipping the record — **which test 4 catches**, since twenty increments from 0 would then restore 19 rather than 0. *(The first draft claimed that mutation stayed green for test 4 and was caught only by test 7; that is wrong, and a wrong mutation prediction is a claim about the evidence — Codex round 3.)* A mutation that is genuinely subtle here: keying coalescence on the address alone rather than address-plus-session-token, which is green until two separate sessions edit the same brick.

**Not in this story**: any UI, and the `UndoManager` bridge. This story's stack is complete and headless. The **plain toolbar undo/redo pair is US-408's**, because that story introduces destructive deletion whose justification depends on undo being reachable; the **bridge, the announcements and the totality proof are US-411's**. *(This line said "both are US-411's" until Codex round 3 moved the toolbar pair forward.)*

## References

- ADR-006 (bounded snapshot stack, coalesced per gesture, never persisted), ADR-036 (reserved — this story writes it)
- ADR-023 — the container swap that makes `endEdit()` idempotency load-bearing
- ADR-032 invariant 2 — and US-309's CI-refuted timing bound, the reason this story's bound is structural
- `Catroid/.../ScriptFragment.java:882-943` — the single-level, no-redo reference; `BrickSpinner.java:179-186` and `FormulaBrick.java:219-225`, the only snapshot triggers
