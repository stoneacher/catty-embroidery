# US-206 — Embroidery bricks wired into the interpreter

**Epic**: E3 Program model & interpreter | **Estimate**: ~5 h | **Depends on**: US-205

**Status**: Planned

**Story**: As the interpreter, I want the eight embroidery bricks to drive the engine's `RunningStitch`, `SewUp`, and `EmbroideryPatternManager`, yielding an `EmbroideryStream`.

The interpreter only *calls* the engine — it never re-implements dedup, interpolation, color-change, or layer logic (those stay owned by the engine per ADR-012/013/015).

## Acceptance criteria
- [ ] Per object: one `RunningStitch` wrapper and one `ActorID`; one shared `EmbroideryPatternManager`. Motion while a pattern is active builds a `NeedleUpdate` and feeds `RunningStitch.update(_:)`; each returned `StagePoint` goes to `manager.addStitch(at:layer: object.zIndex, actor:)` and emits a `stitch` event (Catroid's `Look.positionChanged() → runningStitch.update()` path).
- [ ] `runningStitch(length:)` / `zigZagStitch(length:width:)` / `tripleStitch(length:)` activate the matching engine pattern with **start = current needle position** (Catroid actions construct the stitch reading `sprite.look`). Running/triple length via `interpretInteger`, zigzag length and width via `interpretFloat` (US-203 contract).
- [ ] `stitch`: pause the wrapper → `manager.addStitch` at the needle → `setStartPosition` re-anchor → resume (Catroid `StitchAction`).
- [ ] `setThreadColor(hex:)` → `manager.setThreadColor(hexString:for:)`: invalid hex is a full no-op; before any emission it silently selects the starting color (ADR-015). Emits `colorArmed` as *intent* — the machine-level change record remains the manager's decision.
- [ ] `sewUp` → `SewUp.perform(at:heading:runningStitch:)`, points to the manager; `stopRunningStitch` → `wrapper.stop()`; `writeEmbroideryToFile` emits `finalizeRequested(name:)` and performs **no I/O** (milestone README deviation table; the brick stays modeled for M4/M5).
- [ ] `assembledStream() -> EmbroideryStream` returns `manager.assembled()`.

## Test-first plan
1. `runningStitch(2)` + move 10 → stitches at 0, 2, …, 10 (US-107 lazy-anchor semantics), both as ordered `stitch` events and in `assembledStream()`.
2. `stitch` brick emits exactly one point at the needle and re-anchors: a following running-stitch run measures from there.
3. `setThreadColor` before any emission adds no color change (ADR-015 silent start); a differing set after emission arms exactly one change on the next surviving stitch.
4. `zigZagStitch` and `tripleStitch` activation reproduces the pattern geometry from the US-108/US-109 oracles.
5. `sewUp` emits the 5-point bar tack; `stopRunningStitch` stops stitching (subsequent motion emits nothing).
6. `writeEmbroideryToFile` produces `finalizeRequested` and touches no file system.
7. Two objects with different `zIndex` assemble in layer order with the manager's boundary semantics (US-110 oracle).

## References
- `Catroid/.../content/actions/StitchAction.java`, `RunningStitchAction.java`, `ZigZagStitchAction.java`, `TripleStitchAction.java`, `SewUpAction.java`, `SetThreadColorAction.java`, `StopRunningStitchAction.java`, `WriteEmbroideryToFileAction.kt`, `content/Look.java` (`positionChanged`)
- `EmbroideryEngine`: `RunningStitch`, `SewUp`, `EmbroideryPatternManager` (US-107–US-110)
- ADR-012, ADR-013, ADR-015 in `docs/DECISIONS.md`
