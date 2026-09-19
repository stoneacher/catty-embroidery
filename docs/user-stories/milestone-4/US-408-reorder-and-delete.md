# US-408 — Reorder and delete, pairs intact

**Epic**: E5 Block editor | **Estimate**: ~4 h | **Depends on**: US-402, US-407

**Story**: As a user, I want to drag a brick to a new place and swipe one away — and when I move a loop, I want the whole loop to go with it.

## The off-by-one this story exists to get right

`Script.movingPair(at:to:)` documents its destination as an insertion index into the list **with the block already removed** (`0 ... remaining.count`, verified in the source). SwiftUI's `.onMove` gives a `toOffset` expressed against the array **before** removal. **They are different numbers for every downward move.** The adapter is three lines and it needs its own test, or reorder lands one position off in half of all cases — and "half of all cases" is the kind of bug that looks like a SwiftUI quirk rather than an arithmetic error.

## Settle before implementing

**Does drag-to-reorder work without `EditMode` on iOS 17?** If it needs an `EditButton`, the interaction model gains a mode toggle and this story's estimate goes up. This changes the design, not an implementation detail, so it is settled at story planning — by a Sosumi documentation check and a scratch build, not by recollection (ADR-032 invariant 4).

## Acceptance criteria

- [ ] `.onMove` and `.onDelete` are wired through `EditorCore.apply` — **not** through direct array mutation. Views never mutate the tree (ADR-006 pattern 1).
- [ ] **The destination conversion is explicit and tested**, including a downward move over a multi-brick pair.
- [ ] **Dragging a loop opener moves the whole block.** The model result is correct via `movingPair`.
- [ ] **`loopEnd` rows are `.moveDisabled(true)`.** `.onMove` has no reject hook — you are called *after* the drop and can only decline to mutate, which makes the row spring back with no explanation. Disabling the drag up front is the honest version of the same refusal.
- [ ] **Multi-index moves are handled or refused explicitly.** The closure takes an `IndexSet`; a single-finger drag gives one index but the signature permits more. Handle `count == 1` and refuse the rest, rather than silently moving the first.
- [ ] **Swipe-to-delete on a loop opener deletes the whole loop including its body**, and on a `loopEnd` does the same (ADR-035). **No confirmation dialog** — undo is the affordance that makes one unnecessary, and Catroid has none either.
- [ ] **Pair-aware custom accessibility actions** — Move Up, Move Down, Delete — on every row. A VoiceOver user cannot drag, so these are the **primary** path for them, not a courtesy. "Move up" on a loop opener jumps the whole preceding **sibling block**, using US-402's sibling-jump helper; moving it one index would leave the model balanced while the screen shows a loop swapping with its neighbour's `loopEnd`.
- [ ] The drag **preview** shows one row while the model moves a block, and that mismatch is **acknowledged rather than discovered**: SwiftUI has no multi-row drag preview. Accept it and animate the result, and record the decision. (Collapsible loops would fix it and are not in this milestone.)
- [ ] **Story-specific definition of done**: screenshots including a mid-drag frame, and the VoiceOver action test procedure written as *"rotate to Actions, then swipe"* — US-313b's finding was that the procedure, not the app, was wrong.

## Test-first plan

1. A downward single-brick move produces the expected whole `Program` — the conversion test in its simplest form.
2. A **downward move of a three-brick loop** produces the expected whole program. This is the test the conversion bug fails and test 1 passes.
3. An upward move of the same loop — the direction where the two conventions agree, included so the pair brackets the bug.
4. `.onMove` from a `loopEnd` index is refused and the program is unchanged.
5. An `IndexSet` with two indices is refused and the program is unchanged.
6. `.onDelete` at a loop opener removes opener, body and end; at the `loopEnd` it produces an equal program.
7. Every move and delete leaves every script passing `Script.validate()`.
8. The accessibility "move up" action on a loop opener that follows another loop produces the same program as dragging it above that whole loop — asserted as equality between the two paths.
9. `loopEnd` rows report `moveDisabled`.

**Mutation targets**: the conversion applied in both directions (green for upward, wrong for downward — which is exactly why test 3 exists beside test 2); the sibling jump using `matchingEnd` of the wrong index in a nested script.

## References

- ADR-035 (the move and delete semantics, and the destination convention), ADR-034 (index identity — reinforced here: the row still holds no state), ADR-006 pattern 1
- ADR-031 and US-313b — custom actions live behind the rotor; write the procedure accordingly
- `Sources/ProgramModel/Script+PairedControl.swift:117-140` — `movingPair` and its documented convention
- `Catroid/.../BrickListView.kt:119-144` — the reference hides the body during the drag and shows a one-row ghost, i.e. it has the same visual mismatch and solves it by removing the body from the list. `BrickAdapter.kt:382-384` — the guard that stops a composite being dropped inside itself, which ADR-008's clarification makes unnecessary for us.
