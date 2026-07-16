# US-210 — Coordinate overflow/±121 chokepoint

**Epic**: E3 Program model & interpreter | **Estimate**: ~4 h | **Depends on**: US-206

**Status**: Planned

**Story**: As the engine boundary, I want the two carried-forward coordinate traps closed **inside the engine**, so no caller — interpreter, manager, or direct stream user — can crash it: (a) the exact-boundary disagreement where the interpolation decision rounds the *difference* (`EmbroideryStream.swift`) while record encoding subtracts *individually rounded positions* (`DSTStitchRecord.swift`), so at half-unit stage fractions a move the decision sees as 121 encodes as delta 122 and traps (journal repro: x = 0.125 → 60.75); and (b) finite-but-huge coordinates whose stage→embroidery-unit conversion overflows `Int` at `EmbroideryPoint(converting:)`.

These are engine-side chokepoints — an interpreter-side guard cannot reach (a) at all and would leave direct engine callers exposed to both.

## Acceptance criteria
- [ ] **Boundary trap (a)**: the stream's interpolation decision and the record encoder agree at every input — pinned by making the decision and the encoded delta derive from the same computation (or by an explicit guard at the record seam). Chosen semantics are pinned as an ADR in this story's close-out; at this boundary Catroid itself produces an out-of-range delta (the same rounding mismatch without Swift's trap) — a reference accident, not semantics to port (ADR-012 discipline). ADR-013/015 byte behavior at all ordinary magnitudes is unchanged — the existing golden and boundary tests stay green untouched.
- [ ] **Overflow/non-finite trap (b)**: `EmbroideryPoint(converting:)` (or its single call seam) guards **both** finite stage coordinates whose ×2 conversion exceeds `Int` range (|stage| > ~`Int.max`/2) **and non-finite coordinates (NaN/±∞)** — guarded no-op or clamp, pinned in the same ADR. The ADR-014 guards protect only the pattern path: the public `EmbroideryStream.addStitch` accepts any `StagePoint` and today traps at the conversion (`addStitch(at: StagePoint(x: .infinity, y: 0))` crashes), and the interpreter itself can produce ∞ via `pow` overflow flowing through `placeAt` + `stitch`.
- [ ] The interpreter inherits the safety for free: an adversarial program reaching the manager with extreme coordinates leaves the stream valid and the program running — no `fatalError`, no `Int(_:)` trap.
- [ ] The guard is not over-eager: ordinary >121-unit moves still interpolate per ADR-012, and the ADR-015 ==121 layer-switch behavior is untouched.

## Test-first plan
1. Journal repro at the stream level: previous x = 0.125, target x = 60.75 (decision distance 121, encoded delta 122) → no trap; the pinned semantics hold; the mirrored negative-half case likewise.
2. Direct `EmbroideryStream.addStitch` at |stage| > `Int.max`/2 (e.g. 5e18) and at non-finite coordinates (`StagePoint(x: .infinity, y: 0)`, NaN) → conversion guard fires, no trap, stream stays valid. Same coordinates via `EmbroideryPatternManager.addStitch` **followed by `assembled()`** — the manager stores stage-space ops and converts only during the assembly replay, so the test must assemble to reach the chokepoint.
3. Interpreter-level smoke test through a path that actually reaches conversion (pattern moves are suppressed earlier by the ADR-014 `maxStitchesPerUpdate` guard): `placeAt(5e18, 5e18)` followed by a `stitch` brick **and `assembledStream()`** → guarded, program continues.
4. Not-over-eager: a legal near-boundary conversion (just under `Int.max`/2) still stitches; an ordinary long move still interpolates; the ADR-015 ==121 tie-off tests stay green.

## References
- `docs/workflow-journal.md` 2026-07-13 / 2026-07-14 / 2026-07-16 (carry-forward with minimal repro: decision rounds 121, positions round 0→122)
- `EmbroideryEngine`: `EmbroideryStream.swift` (interpolation decision), `DSTStitchRecord.swift` (delta from rounded positions), `DSTFile.swift` (documented known trap), `Geometry.swift` (`EmbroideryPoint(converting:)`)
- ADR-012 (interpolation), ADR-014 (finiteness guards), ADR-015 (±121 boundary) in `docs/DECISIONS.md`
