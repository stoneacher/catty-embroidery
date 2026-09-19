# US-411 — Undo/redo surfaced, and the totality proof

**Epic**: E5 Block editor | **Estimate**: ~4 h | **Depends on**: US-403, US-408, US-409, US-410

**Story**: As a user, I want undo and redo where I can reach them — a button, a shake, a keyboard shortcut — and I want them to cover *everything* I can do, not most of it.

Last by construction: it is the only story that can prove coverage, because it is the only one that comes after every mutation site exists.

## The `UndoManager` constraint, verified rather than assumed

**`EnvironmentValues.undoManager` is get-only** — confirmed in the iOS 27 SDK's `SwiftUI.swiftinterface` (line 21668), where the property declares only a `get`. So `.environment(\.undoManager, myManager)` **does not compile**, `UIHostingController` overrides `undoManager` with another get-only property, and the manager the environment surfaces is the responder chain's, not one we own. It may also be `nil`.

That settles the architecture rather than constraining it (ADR-036): **the package stack is the truth**, and `UndoManager` is a *trigger surface*. Buttons and shortcuts drive `UndoStack` directly, so the feature is fully functional when the environment value is `nil`. What the bridge buys is shake-to-undo, the three-finger swipe gestures and the system edit menu — accessibility affordances, not logic.

## Acceptance criteria

- [ ] Undo and redo are reachable from the editor's toolbar, disabled precisely when `canUndo`/`canRedo` are false.
- [ ] They drive the **package stack directly**. With no `UndoManager` in the environment, both still work — asserted, not hoped.
- [ ] The `UndoManager` bridge registers one action per committed edit, whose handler re-registers the redo. **A single `loadProgram(_:)` funnel clears both** the package stack and `undoManager.removeAllActions(withTarget:)`. Desync between the two `canUndo`s is the only real hazard in the bridge, and one funnel is the whole mitigation.
- [ ] **Every whole-program replacement goes through that funnel**: picking a sample, loading from disk at launch, starting a blank program. Three callers; all asserted.
- [ ] Undo and redo **announce** what they did via VoiceOver. "Undo" alone is not enough when the change is off-screen — a deleted brick eight rows up is invisible, and the announcement is the only feedback a VoiceOver user gets.
- [ ] **The totality proof**: a test that **enumerates `EditAction`'s cases** and asserts each round-trips through undo to a `Program` equal to the one before it. **Enumeration, not a hand-written list** — a new action case must fail this test rather than quietly escape it. This is exit criterion 2, and it is the criterion this story exists for.
- [ ] Undo after an edit that **voided a run** (ADR-038) restores the program but does **not** resurrect the run or the discarded export file. Undo is an editor affordance; it does not un-cancel a `Task`. Stated explicitly because the opposite is a reasonable thing to assume.
- [ ] **Story-specific definition of done**: screenshots of both enabled and both disabled states, plus a simulator check that shake-to-undo reaches the bridge (or a recorded finding that it does not, with the `#if DEBUG` readout used to establish it).

## Test-first plan

1. **The enumeration test**: for every `EditAction` case, apply it to a seed program, undo, and assert whole-`Program` equality with the original. Built by iterating a case list that a new case must be added to, and a `BrickKind`-style exhaustive switch is what makes the omission a compile error.
2. Redo after undo restores the post-edit program, for every case.
3. `canUndo`/`canRedo` drive the buttons' disabled state.
4. With a `nil` `UndoManager`, undo and redo still work through the buttons.
5. `loadProgram(_:)` clears both stacks, from all three callers.
6. An undo announcement is produced and is localised and non-empty.
7. Undo of a run-voiding edit leaves the run idle and the exporter discarded.
8. Undo across a coalesced US-410 session reverts the whole session, not one keystroke — the integration of US-403's unit behaviour with the real editor.

**Mutation target**: the enumeration test written as a hand-listed array — it passes today and silently stops covering the milestone the moment someone adds a case, which is exactly the "test that cannot fail" pattern (ADR-032 invariant 2) in its slowest-acting form.

## References

- ADR-036 (reserved — US-403 writes it; this story completes it with the bridge), ADR-006 (bounded snapshot stack, never persisted), ADR-038 (an edit voids the run — and undo does not un-void it)
- iOS 27 SDK `SwiftUI.swiftinterface:21668` — `EnvironmentValues.undoManager` is get-only
- `Catroid/.../ScriptFragment.java:882-943` — one level, no redo, and reorder not covered at all: the bar this story clears
