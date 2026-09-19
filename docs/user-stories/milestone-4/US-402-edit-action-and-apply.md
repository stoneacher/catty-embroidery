# US-402 — `EditAction` and the pure `apply` funnel

**Epic**: E5 Block editor | **Estimate**: ~5 h | **Depends on**: US-401

**Story**: As the developer, I want exactly one pure function through which a program can change, so that undo, autosave and run-invalidation each have a single place to hook and no view can mutate the tree behind their backs.

This is ADR-006's pattern 1 made concrete, and the milestone's load-bearing story. Every later mutation — palette add, drag reorder, swipe delete, parameter change, rename — is one of five cases here.

## What this story creates

```swift
public enum EditAction: Equatable, Sendable {
    case insert(BrickKind, at: BrickAddress)
    case delete(at: BrickAddress)
    case move(from: BrickAddress, to: Int)          // post-removal insertion index
    case replaceBrick(at: BrickAddress, with: Brick) // same-kind only
    case renameProgram(String)
}

public enum EditResult: Equatable, Sendable { case applied(Program), rejected(EditRejection) }
public enum EditorCore { public static func apply(_ action: EditAction, to program: Program) -> EditResult }
```

plus `EditRejection`, and the **pair-aware sibling-jump helper** that US-408's accessibility actions need (`the index of the previous/next sibling block, skipping over a whole nested pair`) — a pure function that belongs beside `range(ofPairAt:)`, not in a view.

## Acceptance criteria

- [ ] `apply` is **pure, total and non-throwing** (ADR-033). No index, no address and no malformed action traps it; every path returns an `EditResult`. Rejections are `Equatable` and carry *which* rule was broken.
- [ ] **`insert` of a loop opener inserts two bricks**, opener and `.loopEnd`, from US-401's template. The resulting script passes `Script.validate()`.
- [ ] **`insert(.loopEnd, …)` is rejected** with `.cannotInsertLoopEnd`. It is the only way an action could mint an unbalanced script.
- [ ] **`delete` at a loop opener removes the whole `range(ofPairAt:)`** — opener, body and `loopEnd` (ADR-035, Catroid parity). **`delete` at a `loopEnd` redirects to its opener** and has the identical effect, rather than being rejected.
- [ ] **`move` from a loop opener delegates to `Script.movingPair(at:to:)`**, wrapping — never restating — its `ScriptMoveError`. **`move` from a `loopEnd` is rejected**: it is the one move that can split a pair.
- [ ] **`replaceBrick` is rejected unless the replacement has the same `BrickKind`**, with `.cannotChangeBrickKind(from:to:)`. This is what makes it a parameter edit and keeps the pair invariant without re-validating.
- [ ] **Balance is *preserved*, not *enforced*** — and the distinction is the criterion. For a program whose scripts all pass `Script.validate()`, every `.applied` result also passes it on every script. For a program that is **already** unbalanced, `apply` neither repairs nor rejects it: the imbalance survives untouched. *(Corrected at Codex round 1. The first draft said "applying any action to **any** program either validates or is rejected", which is false by simple counterexample — `.renameProgram("New")` on a program containing a bare `[.loopEnd]` returns `.applied` and the script still fails `validate()`. `Script+PairedControl.swift:117-120` already says `movingPair` preserves rather than enforces global balance, so the overclaim contradicted the primitive it wraps.)*
- [ ] Nothing in `EditorCore` can **introduce** an imbalance into a balanced program. That is the reachability half, and it is what exit criterion 4 actually rests on — the app only ever starts from a balanced program (a sample, or the blank program), so unreachability is the guarantee that matters.
- [ ] A rejected action returns the rejection **and nothing else** — no partially mutated program, which value semantics give for free but which is asserted rather than assumed.

## Test-first plan

1. Each of the five cases, applied to a known program, produces a specific expected whole `Program` — asserted as the entire value (ADR-006 pattern 3), not field by field.
2. `insert(.repeatLoop, at:)` yields a balanced script; `Script.validate()` does not throw.
3. `insert(.loopEnd, at:)` is exactly `.rejected(.cannotInsertLoopEnd)`.
4. `delete` at an opener of a loop containing three bricks removes five elements (opener + 3 + end), and the surrounding bricks are untouched.
5. `delete` at that loop's `loopEnd` produces a program **equal** to the result of test 4 — the redirect asserted as equality against the other path, not as its own hand-written expectation.
6. `move` of a loop opener over a sibling loop relocates the whole block; the result is balanced and equals the expected whole program.
7. `move` from a `loopEnd` is `.rejected(.cannotMoveLoopEnd(…))`.
8. `replaceBrick` with a different kind is `.rejected(.cannotChangeBrickKind(from:to:))`; with the same kind it replaces exactly that one brick.
9. Out-of-bounds addresses in all four addressed cases return `.addressOutOfBounds`, and the destination out of range returns `.destinationOutOfBounds` — the totality tests. Include `Int.max` and a negative index.
10. **The invariant property**: over a generated sequence of actions applied to a **balanced** seed program, every `.applied` result passes `Script.validate()`. Seeded deterministically so a failure is reproducible.
10b. **The preservation counterpart**: applying `.renameProgram` — and each addressed action that targets a *different*, balanced script — to a program containing an already-unbalanced script leaves that imbalance exactly as it was, and does **not** reject. This is the test that would have caught the first draft's overclaim.
11. The sibling-jump helper: on a script with a loop between two leaf bricks, "previous sibling" from the brick after the loop is the loop's **opener** index, not its `loopEnd`.

**Mutation targets** (ADR-032 invariant 2), because several of these will first go red as compile failures: delete-at-opener using `matchingEnd` exclusive instead of inclusive; the `loopEnd` redirect resolving to the wrong opener in a nested script; the same-kind guard comparing the brick rather than the kind (which would pass for every test that changes a value and fail only for one that does not).

## References

- ADR-033 (pure, total, non-throwing, and why this diverges from the repo's throwing precedent), ADR-035 (every semantic decision above), ADR-034 (index addressing)
- ADR-006 pattern 1 (the single funnel) and pattern 3 (assert the whole `Program`)
- ADR-008 + 2026-07-20 clarification — the move primitive this story wraps
- `Sources/ProgramModel/Script+PairedControl.swift:117-140` — `movingPair`, and its **post-removal** destination convention
- `Catroid/.../BrickController.java:65-81`, `ForeverBrick.java:41` — delete takes the body
