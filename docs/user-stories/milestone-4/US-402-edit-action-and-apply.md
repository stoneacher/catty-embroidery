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
- [ ] **`insert` of a loop opener inserts two bricks**, opener and `.loopEnd`, from US-401's template. **For a balanced script**, the result passes `Script.validate()`. The qualifier is load-bearing: inserting a repeat into `[loopEnd, moveNSteps(10)]` yields `[loopEnd, moveNSteps(10), repeatLoop(10), loopEnd]`, which the preservation rule below requires be *accepted* and which does not validate — so an unconditional promise here would contradict it *(Codex round 3)*.
- [ ] **`insert(.loopEnd, …)` is rejected** with `.cannotInsertLoopEnd`. It is the only way an action could mint an unbalanced script.
- [ ] **`delete` at a loop opener removes the whole `range(ofPairAt:)`** — opener, body and `loopEnd` (ADR-035, Catroid parity). **`delete` at a `loopEnd` redirects to its opener** and has the identical effect, rather than being rejected.
- [ ] **`move` from a loop opener delegates to `Script.movingPair(at:to:)`**, wrapping — never restating — its `ScriptMoveError`. **`move` from a `loopEnd` is rejected**: it is the one move that can split a pair.
- [ ] **`replaceBrick` is rejected unless the replacement has the same `BrickKind`**, with `.cannotChangeBrickKind(from:to:)`. This is what makes it a parameter edit and keeps the pair invariant without re-validating.
- [ ] **Balance is *preserved*, not *enforced*** — and the distinction is the criterion. For a program whose scripts all pass `Script.validate()`, every `.applied` result also passes it on every script. For a program that is **already** unbalanced, `apply` does not repair it, and **does not reject solely because of an unrelated imbalance** — an imbalance elsewhere in the program, or elsewhere in the same script, leaves the action's own outcome unchanged. It may still reject for its *own* reasons: moving an opener whose matching `loopEnd` is missing is `.unbalancedPair` and **must** stay rejected, because `movingPair` throws it (`Script+PairedControl.swift:124`) and ADR-008 requires it. *(Narrowed at Codex round 2: the first correction over-swung to "neither repaired nor rejected", which contradicted the delegation criterion directly above it — `[repeatLoop(2), moveNSteps(10)]` moved from index 0 must reject.)* *(Corrected at Codex round 1. The first draft said "applying any action to **any** program either validates or is rejected", which is false by simple counterexample — `.renameProgram("New")` on a program containing a bare `[.loopEnd]` returns `.applied` and the script still fails `validate()`. `Script+PairedControl.swift:117-120` already says `movingPair` preserves rather than enforces global balance, so the overclaim contradicted the primitive it wraps.)*
- [ ] Nothing in `EditorCore` can **introduce** an imbalance into a balanced program. That is the reachability half, and it is what exit criterion 4 rests on. **It requires that every program entering the app is balanced, and there are now three doors, not two** *(Codex round 3)*: a sample, the blank program — and, from US-406, **a decoded document**. A version-1 JSON file containing a bare `[loopEnd]` is structurally decodable by the synthesized `Codable` model, and US-404 checks the version but not the balance. **So US-404 gains a balance check at document admission** (refuse and preserve, exactly as it treats an unsupported version), or this criterion and US-408's unconditional validation test are false for any hand-edited file.
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
10c. **The counterpart to the counterpart**: on the unbalanced script `[repeatLoop(2), moveNSteps(10)]`, `move(from: 0, to: …)` **is** rejected with the wrapped `.unbalancedPair`. Without this test, 10b's rule reads as "never reject on an unbalanced program", which is the over-correction Codex round 2 caught.
11. The sibling-jump helper: on a script with a loop between two leaf bricks, "previous sibling" from the brick after the loop is the loop's **opener** index, not its `loopEnd`.

**Mutation targets** (ADR-032 invariant 2), because several of these will first go red as compile failures: delete-at-opener using `matchingEnd` exclusive instead of inclusive; the `loopEnd` redirect resolving to the wrong opener in a nested script; the same-kind guard comparing the whole brick rather than the kind — which **rejects** an ordinary parameter edit (`moveNSteps(10) → moveNSteps(20)`) and accepts only an unchanged brick, so test 8's same-kind half catches it. *(The first draft predicted the opposite effect; Codex round 3. A mutation prediction is itself a claim, and ADR-032 invariant 2 applies to it.)*

## References

- ADR-033 (pure, total, non-throwing, and why this diverges from the repo's throwing precedent), ADR-035 (every semantic decision above), ADR-034 (index addressing)
- ADR-006 pattern 1 (the single funnel) and pattern 3 (assert the whole `Program`)
- ADR-008 + 2026-07-20 clarification — the move primitive this story wraps
- `Sources/ProgramModel/Script+PairedControl.swift:117-140` — `movingPair`, and its **post-removal** destination convention
- `Catroid/.../BrickController.java:65-81`, `ForeverBrick.java:41` — delete takes the body
