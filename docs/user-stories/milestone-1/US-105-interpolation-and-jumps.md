# US-105 — Long-move interpolation and jump handling

**Epic**: E2 Engine | **Estimate**: ~3 h | **Depends on**: US-102, US-103

**Status**: Done — 2026-07-09, PR #7

**Story**: As the engine, I need moves longer than the DST maximum split into intermediate jump stitches, so that any needle path can be encoded regardless of distance.

## Acceptance criteria

The algorithm is pinned to the reference implementations (Catroid `DSTStream.addInterpolatedPoints` and Catty `EmbroideryStream.addInterpolatedStiches` agree here; see ADR-012) — **not** a "clean" reimplementation, because US-106 requires byte-identical golden output:

- [x] A move from P to Q whose delta exceeds 121 embroidery units on either axis emits, in order: a **duplicate of P flagged as jump**, the evenly spaced intermediates flagged as jumps, **Q flagged as jump**, then **Q again as a plain stitch** (delta 0).
- [x] `splitCount = ceil(maxAxisDistanceInUnits / 121)`; intermediate positions are computed and **rounded in stage coordinates before** the ×2 unit conversion (ADR-012 rounding rule).
- [x] Moves with both axes ≤121 units pass through unmodified (no duplicates).
- [x] Transitions between disjoint path segments (needle repositioning without stitching) are emitted as jump stitches.

## Test-first plan
1. Boundary: delta 121 → single plain stitch, no interpolation. Delta 122 → dup-of-previous (jump), midpoint (jump), target (jump), target (plain) — 4 records for the move (splitCount = 2 yields one intermediate in both references; this line originally said 3, corrected during US-105 planning).
2. Golden-adjacent case: (0,0) → (250,0) in stage points (500 units) reproduces the fixture's structure: 6 jump records + final plain target (ST grows by 7), matching `stitch.dst`.
3. Accumulated-rounding test: the sum of emitted deltas equals the exact converted target; intermediates match reference expectations for a diagonal move (port from Catroid `DSTStreamTest`).

## References
- `Catroid/.../embroidery/DSTStream.java` (`addInterpolatedPoints`, MAX_DISTANCE), `DSTStitchCommand.java`, `DSTFileConstantsTest.java`
- `Catty/src/Catty/Embroidery/EmbroideryStream.swift` (`addInterpolatedStiches`)
- ADR-012 in `docs/DECISIONS.md`
