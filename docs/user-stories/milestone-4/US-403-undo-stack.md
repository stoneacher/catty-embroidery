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

**Amended 2026-09-25 at implementation planning, by Sebastian (after a `swift-architect` pass; recorded in ADR-036).** Three changes to the criteria above, each on purpose:

- The stack **owns the working program**, and its public verb is `apply(_ action:, coalescing:) -> EditResult`, which runs `EditorCore.apply` on `current`. `record(before:key:)` is not public. That removes the second copy of the program a view model would otherwise keep in step, and it means a result computed from a stale base cannot be recorded. Tests use real actions (renames for distinct programs, a genuinely rejected action for item 8).
- **`endEdit(_ key:)` closes only the session it names**, and **`abandonEdit()`** is the key-less "clear a session without ending a well-formed one". A key-less `endEdit()` arriving late from a torn-down sheet A would close sheet B's session during a container swap. `beginEdit` supersedes, and `reset(to:)` clears the session while the key serial keeps counting.
- **An applied edit that leaves the program unchanged records nothing** and keeps redo.

Added tests beyond the ten: a late `endEdit` from a superseded key; a superseded key never coalesces and never closes the open session; `abandonEdit`; session → undo → edit starts a new entry; undo seals the entry it exposes; redo seals its entry; a net-zero session leaves no entry; folding at capacity does not evict; the serial survives `reset`; `reset` closes the session; a no-op records nothing; `Sendable`; the per-file no-Foundation scan; and the boundary bindings. The two sealing and net-zero rules came out of `swift-code-reviewer`'s pass, not the plan.

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

**Not in this story**: any UI, and the `UndoManager` bridge. This story's stack is complete and headless. The **plain toolbar undo/redo pair is US-408's**, because that story introduces destructive deletion whose justification depends on undo being reachable; the **bridge, the announcements and the totality proof are US-411's**.

## References

- ADR-006 (bounded snapshot stack, coalesced per gesture, never persisted), ADR-036 (reserved — this story writes it)
- ADR-023 — the container swap that makes `endEdit()` idempotency load-bearing
- ADR-032 invariant 2 — and US-309's CI-refuted timing bound, the reason this story's bound is structural
- `Catroid/.../ScriptFragment.java:882-943` — the single-level, no-redo reference; `BrickSpinner.java:179-186` and `FormulaBrick.java:219-225`, the only snapshot triggers
