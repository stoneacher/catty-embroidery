# US-203 — Brick enum and flat script with paired-control invariant

**Epic**: E3 Program model & interpreter | **Estimate**: ~4 h | **Depends on**: US-201, US-202

**Status**: Done — PR #21

**Story**: As the model, I want scripts and bricks as Codable value types — bricks as an enum in a flat script list where control bricks are begin/end pairs I can move as one unit — so the M4 editor and `.catrobat` interop build on model-tested structure (ADR-008).

## Acceptance criteria
- [x] `Script { header: ScriptHeader, bricks: [Brick] }` and `ScriptHeader` (M2: only `.whenStarted` — Catroid's `StartScript`, whose `WhenStartedBrick` header contributes no action) land here, alongside the `Brick` type they contain; `Object` gains its `scripts: [Script]` array (deferred from US-201 so every story compiles on its own).
- [x] `Brick` is an `indirect enum` with associated values covering the M2 set — motion: `moveNSteps(Formula)`, `turnLeft(Formula)`, `turnRight(Formula)`, `pointInDirection(Formula)`, `placeAt(x:y:)`, `setX`/`setY`, `changeXBy`/`changeYBy`; control: `repeatLoop(times: Formula)`, `forever`, `loopEnd`, `wait(seconds: Formula)`; data: `setVariable(name:to:)`, `changeVariableBy(name:value:)`; embroidery (the eight, mirroring Catroid's `setupEmbroideryCategoryList` order): `stitch`, `setThreadColor(hex: String)`, `runningStitch(length: Formula)`, `zigZagStitch(length:width:)`, `tripleStitch(length: Formula)`, `sewUp`, `stopRunningStitch`, `writeEmbroideryToFile(name: String)`. Catroid `BrickValues` defaults documented alongside (move 10, turn 15, placeAt (100, 200), stitch length 10, zigzag 2/10, color `#ff0000`, wait 1.0 s).
- [x] `loopEnd` is a pure marker retained in the model — never dropped or synthesized away (ADR-008: serialization and the M4 editor depend on the begin/end pair; Catroid's `LoopEndBrick` contributes no action but terminates the loop in the flat list).
- [x] Pair resolution is model logic: `matchingEnd(ofBrickAt:)` / `range(ofPairAt:)` resolve a control brick's `loopEnd` via stack scan, correct under nesting; `validate()` reports unbalanced scripts (begin without end, end without begin).
- [x] Move-a-pair-as-a-unit: a model primitive relocates a control brick together with its matched `loopEnd` and the enclosed range as one contiguous block. Because the block is a complete balanced pair, every in-bounds destination is valid — reinserting it inside another loop *nests* it (ADR-008: nesting is a rendering concern), so the M4 editor can drag a loop into another loop or reorder sibling loops. Only ill-formed moves are rejected (source out of bounds / not a loop opener / unbalanced, or destination out of bounds). This is the ADR-008 invariant the M4 editor builds on — model logic with tests, not view logic. _(Corrected 2026-07-20 after the Codex cross-vendor review round 1: the original "a move that would split a pair is rejected" wording was based on a false premise — a contiguous balanced block can never split a pair; see PR #21 verdict and the workflow journal.)_

## Test-first plan
1. `matchingEnd` on a single loop resolves its `loopEnd`; on nested loops, inner and outer ends resolve to the correct partners.
2. `validate()` flags a `repeatLoop` without `loopEnd` and a stray `loopEnd` without an opener.
3. Moving a `repeatLoop` relocates the whole `[begin … loopEnd]` range as one unit and preserves enclosed order; moving a pair *into* another loop nests it (balanced result), a nested pair moved back to its home is the identity, and sibling loops reorder — while ill-formed moves (bad source, out-of-bounds destination) are rejected. _(Revised — see AC note above.)_
4. Codable round-trip for bricks with `Formula` payloads and for a full `Program` whose object carries a script with a nested loop — whole-value equality.

## References
- `Catroid/.../content/Script.java`, `StartScript.java`, `bricks/WhenStartedBrick.java`
- `Catroid/.../content/bricks/RepeatBrick.java` (CompositeBrick), `LoopEndBrick.java` (pure marker), `ForeverBrick.java`, `WaitBrick.java`
- `Catroid/.../ui/fragment/CategoryBricksFactory.kt` (`setupEmbroideryCategoryList`), `common/BrickValues.java`
- ADR-001, ADR-008 in `docs/DECISIONS.md`
