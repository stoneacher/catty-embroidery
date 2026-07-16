# US-210 — Coordinate overflow/±121 chokepoint

**Epic**: E3 Program model & interpreter | **Estimate**: ~3 h | **Depends on**: US-206

**Status**: Planned

**Story**: As the engine boundary, I want finite-but-huge needle coordinates from bad or extreme formulas guarded at a single documented chokepoint, so an adversarial program can never crash the interpreter — closing the journal carry-forward from US-108/US-109/US-110 (the round-then-subtract delta trap and the `EmbroideryPoint(converting:)` `Int(_:)` trap on huge Doubles).

## Acceptance criteria
- [ ] One documented chokepoint at the interpreter → manager seam (stage → embroidery-unit conversion) guards: non-finite coordinates (NaN/±Inf) → the update is a no-op; finite coordinates whose unit conversion would overflow `Int` → guarded no-op (extending the ADR-014 `maxStitchesPerUpdate` finiteness discipline from per-update deltas to absolute positions). Chosen semantics (no-op vs clamp) are pinned as an ADR in this story's close-out.
- [ ] `moveNSteps` with an astronomically large formula result, and `placeAt` at extreme coordinates, both leave the stream valid and the program running — no `fatalError`, no `Int(_:)` trap.
- [ ] The guard is not over-eager: legal near-boundary coordinates still stitch normally, and the ±121-unit interpolation/tie-off behavior at ordinary magnitudes is untouched (ADR-015 boundary semantics unchanged).

## Test-first plan
1. `moveNSteps(1e12)` while a running stitch is active → guarded (no crash), program continues, stream stays valid.
2. `placeAt(1e18, 1e18)` → overflow guard fires at the conversion chokepoint; no trap.
3. NaN-producing coordinate path → no stitch emitted, needle and pattern anchor unchanged.
4. A legal near-boundary move (just under the guard limit) stitches normally; an ordinary >121-unit move still interpolates per ADR-012.

## References
- `docs/workflow-journal.md` 2026-07-13 / 2026-07-14 / 2026-07-16 (carry-forward: ±121 round-then-subtract delta trap, finite-but-huge conversion trap, with minimal repro)
- ADR-012 (interpolation), ADR-014 (finiteness guards), ADR-015 (±121 boundary) in `docs/DECISIONS.md`
