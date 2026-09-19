# US-411 — Undo/redo surfaced, and the totality proof

**Epic**: E5 Block editor | **Estimate**: ~4 h | **Depends on**: US-403, US-408, US-409, US-410

**Story**: As a user, I want undo and redo where I can reach them — a button, a shake, a keyboard shortcut — and I want them to cover *everything* I can do, not most of it.

Last by construction: it is the only story that can prove coverage, because it is the only one that comes after every mutation site exists.

## The `UndoManager` constraint, verified rather than assumed

**`EnvironmentValues.undoManager` is get-only** — confirmed in the iOS 27 SDK's `SwiftUI.swiftinterface` (line 21668), where the property declares only a `get`. So `.environment(\.undoManager, myManager)` **does not compile**, and the manager the environment surfaces comes from the responder chain. It may also be `nil`. *(Codex round 1 narrowed this: the first draft added "not one we own", which does not follow — `UIHostingController.undoManager` is an overridden getter, and an overridden responder getter **can** return a manager we own. The design does not depend on the stronger claim, so it is dropped rather than defended.)*

That settles the architecture rather than constraining it (ADR-036): **the package stack is the truth**, and `UndoManager` is a *trigger surface*. Buttons and shortcuts drive `UndoStack` directly, so the feature is fully functional when the environment value is `nil`. What the bridge buys is shake-to-undo, the three-finger swipe gestures and the system edit menu — accessibility affordances, not logic.

## Acceptance criteria

- [ ] Undo and redo are reachable from the editor's toolbar, disabled precisely when `canUndo`/`canRedo` are false.
- [ ] They drive the **package stack directly**. With no `UndoManager` in the environment, both still work — asserted, not hoped.
- [ ] **The bridge is synchronised after *every* history transition, not only on load.** `UndoManager` keeps its own operation history and does not observe the package stack, so a toolbar undo — which by the criterion above must drive the package stack directly — leaves the manager holding a registration the stack no longer has. Concrete case *(Codex round 1)*: make edits A and B, undo B from the toolbar; the manager still holds B's undo registration with no matching redo, so system Redo is unavailable and system Undo consumes a stale entry. **A single `loadProgram(_:)` funnel is not sufficient** — the first draft claimed it was. The synchronisation points are: every toolbar undo and redo, every system-driven undo and redo, the close of a coalesced session, and **eviction at the 50-entry bound**, which silently drops a snapshot the manager may still have a registration for.
- [ ] The simplest sufficient design is stated rather than left to implementation taste: **rebuild the manager's registrations from the package stack after every transition** (`removeAllActions(withTarget:)` then register one undo and one redo reflecting current `canUndo`/`canRedo`). It makes desync structurally impossible instead of requiring every future call site to remember.
- [ ] **Every whole-program replacement goes through that funnel**: picking a sample, loading from disk at launch, starting a blank program. Three callers; all asserted.
- [ ] Undo and redo **announce** what they did via VoiceOver. "Undo" alone is not enough when the change is off-screen — a deleted brick eight rows up is invisible, and the announcement is the only feedback a VoiceOver user gets.
- [ ] **The totality proof**, and its mechanism is part of the criterion because the obvious spelling does not work. `EditAction` has **associated values, so it cannot be `CaseIterable`** — and an exhaustive `switch` plus a separately iterated fixture array does not tie the two together: adding a case and handling it in the switch leaves the old array green *(Codex round 1; ADR-026 already records this exact associated-value-enum coverage failure)*. The mechanism must bind case identity to an executable fixture — e.g. a fixture list whose element type is a `(BrickKind-style case tag, EditAction)` pair, with an exhaustive `switch` from `EditAction` to that tag and a test asserting every tag appears. Whatever is chosen, **adding an `EditAction` case must fail to compile or fail the test**, and the story states which.
- [ ] **Each fixture asserts a successful, non-no-op application before undoing.** Otherwise a fixture whose action is `.rejected` leaves the program unchanged, and the round-trip assertion passes while testing nothing — the "test that cannot fail" pattern (ADR-032 invariant 2) in the very test written to prove coverage.
- [ ] **Undo and redo are themselves program mutations, and carry the same consequences an applied edit does** — *without* recording a new undo entry. `EditAction` has five cases and undo is none of them, so US-405's "an applied action voids the run" hook **does not fire for undo** *(Codex round 1)*. Concrete case: edit P→Q, run Q to completion so an export file is prepared, then undo to P — the stale Q run and its prepared `.dst` survive, which is precisely the hazard ADR-038 exists to close. So every successful history transition must **void the run, discard the prepared export, and autosave**, exactly as an applied edit does.
- [ ] Undo does **not** resurrect a previously discarded run or its deleted export file. Undo is an editor affordance; it does not un-cancel a `Task`. Stated explicitly because the opposite is a reasonable thing to assume — and it is the *complement* of the criterion above, not a substitute for it, which is how the first draft got this wrong: it required only the non-resurrection half.
- [ ] **Story-specific definition of done**: screenshots of both enabled and both disabled states, plus a simulator check that shake-to-undo reaches the bridge (or a recorded finding that it does not, with the `#if DEBUG` readout used to establish it).

## Test-first plan

1. **The enumeration test**: for every `EditAction` case, apply it to a seed program, assert the application **succeeded and changed the program**, undo, and assert whole-`Program` equality with the original. The case-to-fixture binding is the mechanism the criterion settles on; a test that omits the "changed the program" step passes for a rejected fixture and proves nothing.
2. Redo after undo restores the post-edit program, for every case.
3. `canUndo`/`canRedo` drive the buttons' disabled state.
4. With a `nil` `UndoManager`, undo and redo still work through the buttons.
5. `loadProgram(_:)` clears both stacks, from all three callers.
6. An undo announcement is produced and is localised and non-empty.
7. Undo of a run-voiding edit leaves the run idle and the exporter discarded.
7b. **Undo of an edit whose program was then run to completion** voids *that* run and discards *its* prepared export — the case the first draft missed. Redo does the same.
7c. Every successful undo and redo triggers an autosave of the resulting program.
7d. A toolbar undo leaves `UndoManager`'s `canUndo`/`canRedo` agreeing with the package stack's; likewise after a redo, after a coalesced session closes, and after the 50-entry bound evicts.
8. Undo across a coalesced US-410 session reverts the whole session, not one keystroke — the integration of US-403's unit behaviour with the real editor.

**Mutation targets**: the enumeration test written as a hand-listed array — it passes today and silently stops covering the milestone the moment someone adds a case, the "test that cannot fail" pattern (ADR-032 invariant 2) in its slowest-acting form. And the bridge synchronised only on `loadProgram`, which is green for every test that does not perform a *toolbar* undo first.

## References

- ADR-036 (reserved — US-403 writes it; this story completes it with the bridge), ADR-006 (bounded snapshot stack, never persisted), ADR-038 (an edit voids the run — and undo does not un-void it)
- iOS 27 SDK `SwiftUI.swiftinterface:21668` — `EnvironmentValues.undoManager` is get-only
- `Catroid/.../ScriptFragment.java:882-943` — one level, no redo, and reorder not covered at all: the bar this story clears
