# US-207 — Golden program: stitch a square

**Epic**: E3 Program model & interpreter | **Estimate**: ~3 h | **Depends on**: US-206

**Status**: Planned

**Story**: As a maintainer, I want a hardcoded "stitch a square" program to produce a deterministic, expected stitch stream, proving the interpreter end-to-end without UI. **The milestone exit criterion is reached here.**

## Acceptance criteria
- [ ] Hardcoded program: `whenStarted` → `setThreadColor` → `runningStitch(length)` → `repeatLoop(4)[moveNSteps(side), turnRight(90)]` → `sewUp` → `writeEmbroideryToFile` — exercising color, pattern activation, loop compilation, motion, tie-off, and the finalize marker in one program.
- [ ] Golden ordered `stitch` events **and** golden `assembledStream()`. Expected values are derived from the engine's own pattern types in a test helper — never from the interpreter under test (the M1 oracle discipline: the reference implementation, not the code being verified, produces the expectation).
- [ ] Incremental consumption on a real program: driving `step()` one tick at a time yields the identical event sequence and assembled stream as `run()` (the roadmap's batch-equivalence exit test, now on a non-trivial program).
- [ ] Determinism: two runs of the same program produce identical events and streams.

## Test-first plan
1. Square program → expected ordered stitches (four sides at the pattern interval, corner turns, sew-up tack), oracle built from `RunningStitchPattern`/`SewUp` directly.
2. `assembledStream()` equals the golden stream: stitch count, positions, single color, `colorChangeCount` 0 (ADR-015 silent start).
3. Step-by-step vs batch equivalence on the square program — events and assembled stream.
4. Re-running the identical program yields identical results.

## References
- Roadmap M2 exit criterion (`docs/ROADMAP.md`)
- `EmbroideryEngine` pattern types as oracle helpers (US-107, US-109)
- ADR-015 in `docs/DECISIONS.md`
