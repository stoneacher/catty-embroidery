# US-402 — `EditAction` and the pure `apply` funnel

**Epic**: E5 Block editor | **Estimate**: ~5 h | **Depends on**: US-401

**Status**: Done — 2026-09-23. Implemented test-first, reviewed by `swift-code-reviewer` and then over **four Codex rounds**, and closed out the same day. All nine acceptance criteria are met and all eleven test-plan items landed, plus the criteria's own worked counterexample (inserting a repeat into `[loopEnd, moveNSteps(10)]` is accepted *and* stays unbalanced), which the eleven items do not reach. **891 engine tests green** (from 829), CI green on `3775122`, SwiftLint clean by exit code. Package-only: no app target, no `pbxproj`, no human Xcode session. PR [#52](https://github.com/stoneacher/catty-embroidery/pull/52).

**Two semantics the story left open were decided by Sebastian on 2026-09-23** and landed as a dated **ADR-035 amendment** rather than staying in doc comments: `delete` removes an unresolvable control brick as a leaf on a malformed script (so a hand-edited file has no undeletable row) while `move` stays rejected on the same input (ADR-008 owns that rule through `movingPair`); and the sibling jump is *siblings only*, answering `nil` at a loop body's boundaries. The latter is an **accessibility gap** — a VoiceOver user cannot move a brick out of a loop, a sighted user can drag it out — and is recorded as its own acceptance criterion in [US-408](US-408-reorder-and-delete.md), which owns the call.

**Review: 11 findings, all valid, none rejected, and the split between the two reviewers is the story's methodological result.** `swift-code-reviewer` found 4 — three *surviving mutants* and the one real code defect (`previousSiblingIndex` returning a plausible index for an unclosed opener while `nextSiblingIndex` refused, which would have offered VoiceOver an action `apply` rejects every time). Codex found 7 across three productive rounds, **every one of them in a test oracle** and not one in the shipped `apply`. Severity **Medium → Medium → Medium → none**: three flat rounds hit the early-escalation threshold, Sebastian chose to run a fourth, and round 4 returned **no findings**, closing the loop on the no-code-changes condition rather than on a count. **24 mutants written against existing code; 24 killed.**

**The most valuable finding was one Codex under-claimed.** It argued the property test's non-vacuity floors were *satisfiable* by a degenerate run and said carefully that this did not prove the seeds degenerate. Strengthening the floors proved they **were** — zero applied replacements on all three seeds, zero pair relocations on one — because the generator replaced each brick with its own kind's `template()` and every brick a run inserts comes from `template()`. That is ADR-032 invariant 2 one layer up: not a test that cannot fail, but a test's own evidence-of-adequacy that could not fail.

**Story**: As the developer, I want exactly one pure function through which a program can change, so that undo, autosave and run-invalidation each have a single place to hook and no view can mutate the tree behind their backs.

This is ADR-006's pattern 1 made concrete, and the milestone's load-bearing story. Every later mutation — palette add, drag reorder, swipe delete, parameter change, rename — is one of five cases here.

## What this story creates

```swift
public enum EditAction: Equatable, Sendable {
 case insert(BrickKind, at: BrickAddress)
 case delete(at: BrickAddress)
 case move(from: BrickAddress, to: Int) // post-removal insertion index
 case replaceBrick(at: BrickAddress, with: Brick) // same-kind only
 case renameProgram(String)
}

public enum EditResult: Equatable, Sendable { case applied(Program), rejected(EditRejection) }
public enum EditorCore { public static func apply(_ action: EditAction, to program: Program) -> EditResult }
```

plus `EditRejection`, and the **pair-aware sibling-jump helper** that US-408's accessibility actions need (`the index of the previous/next sibling block, skipping over a whole nested pair`) — a pure function that belongs beside `range(ofPairAt:)`, not in a view.

## Acceptance criteria

- [x] `apply` is **pure, total and non-throwing** (ADR-033). No index, no address and no malformed action traps it; every path returns an `EditResult`. Rejections are `Equatable` and carry *which* rule was broken.
- [x] **`insert` of a loop opener inserts two bricks**, opener and `.loopEnd`, from US-401's template. **For a balanced script**, the result passes `Script.validate()`. The qualifier is load-bearing: inserting a repeat into `[loopEnd, moveNSteps(10)]` yields `[loopEnd, moveNSteps(10), repeatLoop(10), loopEnd]`, which the preservation rule below requires be *accepted* and which does not validate — so an unconditional promise here would contradict it.
- [x] **`insert(.loopEnd, …)` is rejected** with `.cannotInsertLoopEnd`. It is the only way an action could mint an unbalanced script.
- [x] **`delete` at a loop opener removes the whole `range(ofPairAt:)`** — opener, body and `loopEnd` (ADR-035, Catroid parity). **`delete` at a `loopEnd` redirects to its opener** and has the identical effect, rather than being rejected.
- [x] **`move` from a loop opener delegates to `Script.movingPair(at:to:)`**, wrapping — never restating — its `ScriptMoveError`. **`move` from a `loopEnd` is rejected**: it is the one move that can split a pair.
- [x] **`replaceBrick` is rejected unless the replacement has the same `BrickKind`**, with `.cannotChangeBrickKind(from:to:)`. This is what makes it a parameter edit and keeps the pair invariant without re-validating.
- [x] **Balance is *preserved*, not *enforced*** — and the distinction is the criterion. For a program whose scripts all pass `Script.validate()`, every `.applied` result also passes it on every script. For a program that is **already** unbalanced, `apply` does not repair it, and **does not reject solely because of an unrelated imbalance** — an imbalance elsewhere in the program, or elsewhere in the same script, leaves the action's own outcome unchanged. It may still reject for its *own* reasons: moving an opener whose matching `loopEnd` is missing is `.unbalancedPair` and **must** stay rejected, because `movingPair` throws it (`Script+PairedControl.swift:124`) and ADR-008 requires it.
- [x] Nothing in `EditorCore` can **introduce** an imbalance into a balanced program. That is the reachability half, and it is what exit criterion 4 rests on. **It requires that every program entering the app is balanced, and there are now three doors, not two**: a sample, the blank program — and, from US-406, **a decoded document**. A version-1 JSON file containing a bare `[loopEnd]` is structurally decodable by the synthesized `Codable` model, and US-404 checks the version but not the balance. **So US-404 gains a balance check at document admission** (refuse and preserve, exactly as it treats an unsupported version), or this criterion and US-408's unconditional validation test are false for any hand-edited file.
- [x] A rejected action returns the rejection **and nothing else** — no partially mutated program, which value semantics give for free but which is asserted rather than assumed.

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
10b. **The preservation counterpart**: applying `.renameProgram` — and each addressed action that targets a *different*, balanced script — to a program containing an already-unbalanced script leaves that imbalance exactly as it was, and does **not** reject. The counterexample: `.renameProgram("New")` on a program containing a bare `[.loopEnd]` applies, and the script still fails `validate()`.
10c. **The counterpart to the counterpart**: on the unbalanced script `[repeatLoop(2), moveNSteps(10)]`, `move(from: 0, to: …)` **is** rejected with the wrapped `.unbalancedPair`. Without this test, 10b's rule reads as "never reject on an unbalanced program", which is too strong.
11. The sibling-jump helper: on a script with a loop between two leaf bricks, "previous sibling" from the brick after the loop is the loop's **opener** index, not its `loopEnd`.

## References

- ADR-033 (pure, total, non-throwing, and why this diverges from the repo's throwing precedent), ADR-035 (every semantic decision above), ADR-034 (index addressing)
- ADR-006 pattern 1 (the single funnel) and pattern 3 (assert the whole `Program`)
- ADR-008 + 2026-07-20 clarification — the move primitive this story wraps
- `Sources/ProgramModel/Script+PairedControl.swift:117-140` — `movingPair`, and its **post-removal** destination convention
- `Catroid/.../BrickController.java:65-81`, `ForeverBrick.java:41` — delete takes the body
