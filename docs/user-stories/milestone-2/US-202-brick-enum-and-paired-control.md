# US-202 — Brick enum and flat script with paired-control invariant

**Epic**: E3 Program model & interpreter | **Estimate**: ~4 h | **Depends on**: US-201

**Status**: Planned

**Story**: As the model, I want bricks as a Codable enum in a flat script list where control bricks are begin/end pairs I can move as one unit, so the M4 editor and `.catrobat` interop build on model-tested structure (ADR-008).

## Acceptance criteria
- [ ] `Brick` is an `indirect enum` with associated values covering the M2 set — motion: `moveNSteps(Formula)`, `turnLeft(Formula)`, `turnRight(Formula)`, `pointInDirection(Formula)`, `placeAt(x:y:)`, `setX`/`setY`, `changeXBy`/`changeYBy`; control: `repeatLoop(times: Formula)`, `forever`, `loopEnd`, `wait(seconds: Formula)`; data: `setVariable(name:to:)`, `changeVariableBy(name:value:)`; embroidery (the eight, mirroring Catroid's `setupEmbroideryCategoryList` order): `stitch`, `setThreadColor(hex: String)`, `runningStitch(length: Formula)`, `zigZagStitch(length:width:)`, `tripleStitch(length: Formula)`, `sewUp`, `stopRunningStitch`, `writeEmbroideryToFile(name: String)`. Catroid `BrickValues` defaults documented alongside (move 10, turn 15, placeAt (100, 200), stitch length 10, zigzag 2/10, color `#ff0000`, wait 1.0 s).
- [ ] `loopEnd` is a pure marker retained in the model — never dropped or synthesized away (ADR-008: serialization and the M4 editor depend on the begin/end pair; Catroid's `LoopEndBrick` contributes no action but terminates the loop in the flat list).
- [ ] Pair resolution is model logic: `matchingEnd(ofBrickAt:)` / `range(ofPairAt:)` resolve a control brick's `loopEnd` via stack scan, correct under nesting; `validate()` reports unbalanced scripts (begin without end, end without begin).
- [ ] Move-a-pair-as-a-unit: a model primitive relocates a control brick together with its matched `loopEnd` and the enclosed range as one contiguous block; a move that would split a pair is rejected. This is the ADR-008 invariant the M4 editor builds on — model logic with tests, not view logic.

## Test-first plan
1. `matchingEnd` on a single loop resolves its `loopEnd`; on nested loops, inner and outer ends resolve to the correct partners.
2. `validate()` flags a `repeatLoop` without `loopEnd` and a stray `loopEnd` without an opener.
3. Moving a `repeatLoop` relocates the whole `[begin … loopEnd]` range as one unit and preserves enclosed order; a target index inside another pair's range that would split it is rejected.
4. Codable round-trip for bricks with `Formula` payloads and for a script containing a nested loop — whole-script equality.

## References
- `Catroid/.../content/bricks/RepeatBrick.java` (CompositeBrick), `LoopEndBrick.java` (pure marker), `ForeverBrick.java`, `WaitBrick.java`
- `Catroid/.../ui/fragment/CategoryBricksFactory.kt` (`setupEmbroideryCategoryList`), `common/BrickValues.java`
- ADR-001, ADR-008 in `docs/DECISIONS.md`
