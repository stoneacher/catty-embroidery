# US-107 — Running stitch pattern

**Epic**: E2 Engine | **Estimate**: ~3 h | **Depends on**: US-102

**Status**: Done — 2026-07-13, PR #10

**Story**: As a program, I want a running stitch pattern that drops stitches at a fixed interval along the needle's path, so that moving the needle produces a continuous stitched line.

## Acceptance criteria
- [x] `StitchPattern` protocol: patterns receive `NeedleUpdate { position, heading }` — **position and heading**, because zigzag and sew-up derive their geometry from the needle's heading, not the movement vector (they differ under goto/glide; Catty's own protocol passes rotation). Angle convention per ADR-007: degrees, 0° = up, x via sin, y via cos.
- [x] Patterns are pure state machines: `mutating func update(_: NeedleUpdate) -> [StagePoint]` **returns** stitch positions instead of writing into the stream — the stream stays the single writer (owning interpolation, dedup, and pending flags), and patterns test without a stream. *(Amended 2026-07-10, was `-> [Stitch]`: `Stitch` carries converted embroidery units plus jump/color flags, all of which are the stream's authority — ADR-012 interpolation happens in stage coordinates before unit conversion, so patterns emit stage-space positions.)*
- [x] Two distinct types, mirroring Catroid: a **lifecycle wrapper** (`RunningStitch`: one per actor; activate / pause / resume / stop) and the **pattern state machine** (`RunningStitchPattern(length:)`) it delegates to — US-109's pause-around-sew-up composes on the wrapper.
- [x] `RunningStitchPattern(length:)`: stitches every `length` units along the path, interpolated linearly between update points, matching `SimpleRunningStitch`. The anchor stitch at the start position is emitted **lazily on the first update that crosses the length threshold** (the `first` flag in `interpolateStitches`) — not at activation.
- [x] Movement shorter than `length` accumulates until the threshold is crossed (no stitch spam, no lost distance).

## Test-first plan
1. Straight-line test: move 10 units with length 2 → stitches at 0,2,4,6,8,10 (the 0-stitch arriving with the first threshold-crossing update).
2. Multi-segment path test (direction change mid-line) with interpolated positions ported from `SimpleRunningStitchTest`.
3. Accumulation test: several sub-length moves eventually emit exactly one stitch at the right position.
4. Lifecycle tests on the wrapper, ported as-is from `RunningStitchTest`: no stitches while paused/stopped; resume continues without drift.

## References
- `Catroid/.../embroidery/SimpleRunningStitch.java`, `RunningStitch.java`, `SimpleRunningStitchTest.java`, `RunningStitchTest.java`
- `Catty/src/Catty/Embroidery/Pattern/RunningStitchPattern.swift` (`spriteDidMove(to:rotation:)`)
- ADR-007, ADR-012 in `docs/DECISIONS.md`
