# US-408 — Reorder and delete, pairs intact

**Epic**: E5 Block editor | **Estimate**: ~5 h (grew to ~7 h — see below) | **Depends on**: US-402, US-403, US-407

**Status**: Done — 2026-09-29, [PR #63](https://github.com/stoneacher/catty-embroidery/pull/63) (pending merge). Test-first in two rounds, each with a `[red]` commit (`89ac9cb`, `9995d29`). Reviewed by `swift-code-reviewer` (exhaustive fuzz over 3 280 scripts; no critical findings, four gaps fixed, one of which became the Move Into Loop pair by Sebastian's decision) and by **one Codex round with no findings**, which ends the loop on condition 1. All acceptance criteria met except "animate the result", which is deliberately not met as written (see below). The manual VoiceOver pass is bundled with M4's end-of-milestone accessibility pass; its procedure for this story is written below.

**Story**: As a user, I want to drag a brick to a new place and swipe one away — and when I move a loop, I want the whole loop to go with it.

## The off-by-one this story exists to get right

`Script.movingPair(at:to:)` documents its destination as an insertion index into the list **with the block already removed** (`0... remaining.count`, verified in the source). SwiftUI's `.onMove` gives a `toOffset` expressed against the array **before** removal. **They differ for every downward move**, and the adapter needs its own test or reorder lands wrong in half of all cases — the kind of bug that looks like a SwiftUI quirk rather than an arithmetic error.

**The conversion is not "subtract one".** It is:

```
destination = toOffset − count(removed indices < toOffset)
```

For a single brick that is a difference of one; **for a pair it is the whole block length**. Concrete: moving `[R, A, E]` below `B` in `[R, A, E, B]` gives `toOffset = 4` and `destination = 1` — a difference of **three**. Two consequences the implementation must handle rather than discover: blindly subtracting the block length whenever `toOffset > source` can produce a **negative** destination, and a drop **inside the moving pair's own original range** must resolve to a **no-op** rather than to an out-of-range index.

## Settle before implementing

**Does drag-to-reorder work without `EditMode` on iOS 17?** If it needs an `EditButton`, the interaction model gains a mode toggle and this story's estimate goes up. This changes the design, not an implementation detail, so it is settled at story planning — by a Sosumi documentation check and a scratch build, not by recollection (ADR-032 invariant 4).

## Acceptance criteria

- [x] `.onMove` and `.onDelete` are wired through `EditorCore.apply` — **not** through direct array mutation. Views never mutate the tree (ADR-006 pattern 1).
- [x] **The destination conversion is explicit and tested**, including a downward move over a multi-brick pair.
- [x] **Dragging a loop opener moves the whole block.** The model result is correct via `movingPair`.
- [x] **`loopEnd` rows are `.moveDisabled(true)`.** `.onMove` has no reject hook — you are called *after* the drop and can only decline to mutate, which makes the row spring back with no explanation. Disabling the drag up front is the honest version of the same refusal.
- [x] **Multi-index moves are handled or refused explicitly.** The closure takes an `IndexSet`; a single-finger drag gives one index but the signature permits more. Handle `count == 1` and refuse the rest, rather than silently moving the first.
- [x] **Swipe-to-delete on a loop opener deletes the whole loop including its body**, and on a `loopEnd` does the same (ADR-035). **No confirmation dialog** — undo is the affordance that makes one unnecessary, and Catroid has none either.
- [x] **Therefore a reachable undo ships *in this story*, not in US-411**. ADR-035 justifies deleting five bricks without confirmation by pointing at undo, and the ROADMAP promises mutations "undoable from day one" — but US-403's stack is headless and US-411 is three stories away, so at this story's handover a user could destroy a loop with **no recovery reachable from the UI**. A plain toolbar undo/redo pair driving the US-403 stack is enough; **US-411 keeps the `UndoManager` bridge, the announcements and the totality proof**.
- [x] **The consequences of a history transition ship with the buttons, not with the bridge**. Undo restores a snapshot from outside the `EditAction` vocabulary, so US-405's applied-edit hook does **not** fire for it, and `RunViewModel.reset()` / `onRunDiscarded` are explicit calls that observe nothing automatically. Concrete case at this story's handover: delete a loop from P to get Q, run Q to completion, toolbar-undo back to P — and Q's preview and its prepared `.dst` stay shareable, violating ADR-026's export consistency and the ADR-038 rule. **Every successful undo and redo here must void the run, discard the prepared export, and autosave, without recording a new undo entry.** US-411 re-verifies the same through the bridge rather than introducing it. The estimate carries it — this story is ~5 h rather than ~4 h for that reason — and if it runs over, the toolbar pair is the piece to split out and land *before* delete, never after.
- [x] **Pair-aware custom accessibility actions** — Move Up, Move Down, Delete — on every row **that can act on them**. A `loopEnd` row is the exception and needs a stated policy rather than an advertised action that always fails: ADR-035 rejects a move sourced from a `loopEnd` and the row is `.moveDisabled(true)`, so offering Move Up on `[move(1), repeat(2), move(10), loopEnd]` index 3 returns `.cannotMoveLoopEnd` every time. **Choose and test one**: omit the two move actions on end rows, or redirect them to the opener the way Delete already does. Delete stays on every row, since its redirect is already specified. A VoiceOver user cannot drag, so these are the **primary** path for them, not a courtesy. "Move up" on a loop opener jumps the whole preceding **sibling block**, using US-402's sibling-jump helper; moving it one index would leave the model balanced while the screen shows a loop swapping with its neighbour's `loopEnd`.
- [x] **Inherited from US-402, decided 2026-09-23, and it is an accessibility gap rather than a free win**: the sibling-jump helper is *siblings only*. It answers `nil` at a loop body's top and bottom, because the enclosing opener is a brick's **parent**, not its neighbour — so a Move Up/Move Down driven straight from it **cannot move a brick out of a loop**, while a sighted user can drag it out. It also answers `nil` in both directions for a block whose extent cannot be resolved, so no action is offered that `apply` would then always reject. This story owns the call: accept the gap and state it, or add a distinct "move out of loop" verb (a different action with its own undo entry, not a widening of the helper). Whichever is chosen, say so — the gap is not to be inherited silently a second time. See ADR-035's 2026-09-23 amendment.
- [x] The drag **preview** shows one row while the model moves a block, and that mismatch is **acknowledged rather than discovered**: the iOS-17-compatible `List` + `.onMove` path has no multi-row drag preview. The limitation belongs to this path and the iOS 17 floor, not to SwiftUI as such — newer platforms and other drag APIs do support multi-item previews. Accept it and animate the result, and record the decision. (Collapsible loops would fix it and are not in this milestone.)
- [x] **Story-specific definition of done**: screenshots including a mid-drag frame, and the VoiceOver action test procedure written as *"rotate to Actions, then swipe"* — US-313b's finding was that the procedure, not the app, was wrong.

## Decisions and deviations (2026-09-29)

- **Settled at planning: drag needs no `EditMode`.** A scratch build (iOS 26.5 simulator, throwaway worktree) showed a long press lifting a row in a plain `List` + `ForEach.onMove`, with `toOffset` pre-removal as this story warns. **No iOS 17 runtime is installed**, so the floor rests on the API's documented availability, not on a build. Screenshot `docs/screenshots/us-408/00-probe-no-editmode-mid-drag.png`.
- **`loopEnd` rows: the move actions are omitted** (Sebastian), not redirected. Delete stays and redirects. An unclosed opener is `.moveDisabled` too.
- **The out-of-loop gap: closed, with a verb pair** (Sebastian): *Move Above Loop* / *Move Below Loop*, offered only at a body's first / last block.
- **…and its mirror, into a loop** (Sebastian, at `swift-code-reviewer`'s finding that the move-out pair still left VoiceOver 4 arrangements short of the drag on `[A, repeat, B, end]`): *Move Into Loop Above* / *Below*. With the four above, the six actions reach **exactly** what a drag reaches — asserted as a reachability property on three fixtures. This and the move-out pair are why the estimate grew by ~2 h.
- **Undo/redo in the bottom bar** (Sebastian), both placements, disabled without history; no ⌘Z (US-411's bridge owns the keyboard).
- **`onEditApplied` → `onProgramChanged`**, fired by every successful undo/redo too, so the run is voided, the prepared file discarded and the program autosaved without a new history entry (ADR-038 and ADR-037 amendments).
- **"Animate the result" is not met as written.** Rows are identified by index (ADR-034), so after a move only contents change, and after a delete the *last* ids vanish; an explicit animation would show the wrong rows leaving. The list's own drop animation is kept and no `withAnimation` is added (ADR-035 amendment).
- **Found and backlogged**: the loop-end row's symbol is the Undo glyph (US-321).

## VoiceOver procedure (for the bundled M4 accessibility pass)

Custom actions are behind the rotor (US-313b's finding: the procedure, not the app, was what failed). On Square Coil:

1. Swipe to "Set thread colour to #f59e0b" (between the two loops). **Rotate the rotor to Actions, then swipe up/down** through them. Expect exactly: Move Up, Move Down, Move Into Loop Above, Move Into Loop Below, Delete — in some order. ("Repeat 13 times", with a brick on each side, offers Move Up, Move Down, Delete.) Note the spoken order (ADR-031 found chained actions spoken in reverse) and **whether Delete appears twice** (`.onDelete` may add a system one; if so, drop ours from the view — the presentation keeps `delete` for the tests).
2. On "Repeat 13 times", choose Move Up. Expect VoiceOver to land on "Repeat 13 times" at its new position and read it — **not** the brick that now holds the old index. Choose Move Up again; the same loop should move again.
3. Swipe to "Move "Side" steps" (first in a body). Expect Move Above Loop among its actions; choose it and hear it read at depth 0.
4. Swipe to an "End of repeat" row. Expect Delete only; choose it: the whole loop goes. Double-tap Undo in the bottom bar: it comes back.
5. After a **Delete action**, note where focus lands (it stays on the index, which now holds the next brick — the reviewer flagged this; judge whether it reads acceptably).
6. With six actions possible on one row, judge whether the list is navigable.

## Test-first plan

1. A downward single-brick move produces the expected whole `Program` — the conversion test in its simplest form.
2. A **downward move of a three-brick loop** produces the expected whole program. This is the test the conversion bug fails and test 1 passes.
3. An upward move of the same loop — the direction where the two conventions agree, included so the pair brackets the bug.
3b. A drop **within the moving pair's own original range** is a no-op, and the program is unchanged.
3c. A downward move to the very end produces the expected whole `Program`. **It does not discriminate the block-length mutant**: at that destination `n − L == remaining.count` exactly (`[R,A,E,B]`, offset 4, length 3 → 1), so both the correct adapter and the unconditional subtraction agree there. It catches a naive *subtract-one* for a multi-brick block, which is its actual value. **Test 3 is what catches the block-length mutant.**
4. `.onMove` from a `loopEnd` index is refused and the program is unchanged.
5. An `IndexSet` with two indices is refused and the program is unchanged.
6. `.onDelete` at a loop opener removes opener, body and end; at the `loopEnd` it produces an equal program.
7. Every move and delete leaves every script passing `Script.validate()`.
8. The accessibility "move up" action on a loop opener that follows another loop produces the same program as dragging it above that whole loop — asserted as equality between the two paths.
9. `loopEnd` rows report `moveDisabled`.
9b. The chosen `loopEnd` move-action policy: either the actions are absent from an end row, or invoking one produces the same program as invoking it on the opener. Asserted against whichever is chosen — an advertised action that always rejects is the failure this replaces.

## References

- ADR-035 (the move and delete semantics, and the destination convention), ADR-034 (index identity — reinforced here: the row still holds no state), ADR-006 pattern 1
- ADR-031 and US-313b — custom actions live behind the rotor; write the procedure accordingly
- `Sources/ProgramModel/Script+PairedControl.swift:117-140` — `movingPair` and its documented convention
- `Catroid/.../BrickListView.kt:119-144` — the reference hides the body during the drag and shows a one-row ghost, i.e. it has the same visual mismatch and solves it by removing the body from the list. `BrickAdapter.kt:382-384` — the guard that stops a composite being dropped inside itself, which ADR-008's clarification makes unnecessary for us.
