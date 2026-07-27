# US-208 — Golden program: stitch a star

**Epic**: E3 Program model & interpreter | **Estimate**: ~3 h | **Depends on**: US-207

**Status**: Done — 2026-07-27

**Story**: As a maintainer, I want a hardcoded "stitch a star" program (turn 144°, a second pattern type, a mid-program color change) to produce a deterministic golden stream, exercising turn arithmetic, zigzag/triple geometry, and ADR-015 color semantics end-to-end.

## Acceptance criteria
- [x] Hardcoded five-pointed-star program under `zigZagStitch`, with a `setThreadColor` before stitching and a differing `setThreadColor` mid-program. **Deviation**: the walk is `repeatLoop(2)` · `setThreadColor` · `repeatLoop(3)`, not one `repeatLoop(5)` — the AC's single loop and a mid-program colour cannot both hold literally, and between the loops is the only shape that executes the brick exactly once and partitions the stream unambiguously by colour (Sebastian, 2026-07-27).
- [x] Golden ordered events and `assembledStream()`, pinned both ways: `GoldenStarLiterals` (hand-derived, independent) and `GoldenStarOracle` (differential replay through the engine's pattern types).
- [x] Heading accumulation is exact: 5 × 144° = 720° ≡ 0° mod 360, asserted with `==` against the closing `needleMoved` event.
- [x] The mid-program colour set arms exactly one machine-level change (ADR-015): `colorChangeCount == 1`, the change rides record 9, and `DSTHeader`'s CO field reads 2.
- [x] Step-by-step == batch; two runs identical; a mid-run copy replays the identical tail.

## Test-first plan
1. Star geometry golden: five sides; the path closes at the start point **within the ADR-014 tolerance** (the residue is 1.78e-15, not ~1e-16 as estimated when planning), while the heading returns to exactly 0° (mod-360 normalization is exact).
2. The pattern's per-side stitch geometry matches its US-108/US-109 oracle.
3. Exactly one color change in the assembled stream; first set is silent (ADR-015).
4. Step-vs-batch equivalence and re-run determinism on the star program.

## References
- US-207 (oracle discipline), US-108/US-109 pattern oracles
- ADR-014 (heading normalization), ADR-015 (color semantics) in `docs/DECISIONS.md`

## Outcome

Test-only; no production code needed changing. 21 tests across two suites, 323 green.
`side 20`, `length 5`, `width 4`, `turn 144` — 26 records, 39 events, 15 ticks.

Two findings worth carrying forward:

- **The golden is pinned to Apple platforms' libm** and now says so. Side 4's exact
  length is 1.878e-15 below 20 and correctly rounds *down*; Darwin's `hypot` is
  0.53 ulp high and rounds it up, and that error is the only reason the side emits
  four stitch intervals. Kept deliberately, guarded by
  `theGoldenDependsOnLibmRoundingOfHypot`, and pinned as **ADR-019** — coordinate
  tolerance (ADR-014) and structure-determining threshold crossings are different
  problems, and only the first has a tolerance.
- **Parameter screening must run against the engine, not a model of it.** The first
  attempt screened side/length pairs in Python, whose `math.hypot` returns the
  correctly rounded result for these operands where Darwin's libm does not, so the
  screen recommended parameters the engine rejects and rejected the ones it accepts.
  (Neither project guarantees correct rounding for `hypot`; the point is that two
  implementations disagree, not that either is specified — Codex US-208.)

**Manual Ink/Stitch verification: not needed.** No DST file is produced — the CO
assertion reads header bytes in memory — and no byte-level semantics changed.
