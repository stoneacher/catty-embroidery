# US-208 — Golden program: stitch a star

**Epic**: E3 Program model & interpreter | **Estimate**: ~3 h | **Depends on**: US-207

**Status**: Planned

**Story**: As a maintainer, I want a hardcoded "stitch a star" program (turn 144°, a second pattern type, a mid-program color change) to produce a deterministic golden stream, exercising turn arithmetic, zigzag/triple geometry, and ADR-015 color semantics end-to-end.

## Acceptance criteria
- [ ] Hardcoded five-pointed-star program: `repeatLoop(5)[moveNSteps(side), turnRight(144)]` under `zigZagStitch` (or `tripleStitch`), with a `setThreadColor` before stitching and a differing `setThreadColor` mid-program.
- [ ] Golden ordered events and `assembledStream()`; oracle derived from the engine's pattern types (US-207 discipline).
- [ ] Heading accumulation is exact: 5 × 144° = 720° ≡ 0° mod 360 — the needle ends pointing where it started (US-204 normalization).
- [ ] The mid-program color set arms exactly one machine-level change (ADR-015); the stream's `colorChangeCount` is 1, so DST `CO = changes + 1 = 2` at the header level.
- [ ] Step-by-step == batch; two runs identical.

## Test-first plan
1. Star geometry golden: five sides, closing exactly at the start point, heading back to 0°.
2. The pattern's per-side stitch geometry matches its US-108/US-109 oracle.
3. Exactly one color change in the assembled stream; first set is silent (ADR-015).
4. Step-vs-batch equivalence and re-run determinism on the star program.

## References
- US-207 (oracle discipline), US-108/US-109 pattern oracles
- ADR-014 (heading normalization), ADR-015 (color semantics) in `docs/DECISIONS.md`
