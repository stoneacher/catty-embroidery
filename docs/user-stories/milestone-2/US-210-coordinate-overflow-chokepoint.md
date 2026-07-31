# US-210 — Coordinate overflow/±121 chokepoint

**Epic**: E3 Program model & interpreter | **Estimate**: ~4 h | **Depends on**: US-206

**Status**: Done — 2026-07-31. Semantics pinned as ADR-020 (encodable-delta interpolation trigger, failable conversion, guarded no-ops, bounded split count).

**Story**: As the engine boundary, I want the two carried-forward coordinate traps closed **inside the engine**, so no caller — interpreter, manager, or direct stream user — can crash it: (a) the exact-boundary disagreement where the interpolation decision rounds the *difference* (`EmbroideryStream.swift`) while record encoding subtracts *individually rounded positions* (`DSTStitchRecord.swift`), so at half-unit stage fractions a move the decision sees as 121 encodes as delta 122 and traps (journal repro: x = 0.125 → 60.75); and (b) finite-but-huge coordinates whose stage→embroidery-unit conversion overflows `Int` at `EmbroideryPoint(converting:)`.

These are engine-side chokepoints — an interpreter-side guard cannot reach (a) at all and would leave direct engine callers exposed to both.

## Acceptance criteria
- [x] **Boundary trap (a)**: the stream's interpolation decision and the record encoder agree at every input — pinned by making the decision and the encoded delta derive from the same computation (or by an explicit guard at the record seam). Chosen semantics are pinned as an ADR in this story's close-out; at this boundary Catroid itself produces an out-of-range delta (the same rounding mismatch without Swift's trap) — a reference accident, not semantics to port (ADR-012 discipline). ADR-013/015 byte behavior at all ordinary magnitudes is unchanged — the existing golden and boundary tests stay green untouched. — **Resolved as neither alternative exactly: the decision takes the *maximum* of the two measures.** Keeping only Catroid's difference rounding leaves the trap; deriving the decision *only* from the encoded delta would have closed it but diverged in the mirror case (difference 122, encoded 121 — e.g. 0.25 → 61.0), where Catroid splits and is right. The max is a strict superset of Catroid's interpolation: it adds splits only where the reference emits a corrupt record. Every golden stayed green untouched, including the two US-106 fixtures, US-209's committed `square.dst`, and the ADR-015 ±60.75 clause pins.
- [x] **Overflow/non-finite trap (b)**: `EmbroideryPoint(converting:)` (or its single call seam) guards **both** finite stage coordinates whose ×2 conversion exceeds `Int` range (|stage| > ~`Int.max`/2) **and non-finite coordinates (NaN/±∞)** — guarded no-op or clamp, pinned in the same ADR. The ADR-014 guards protect only the pattern path: the public `EmbroideryStream.addStitch` accepts any `StagePoint` and today traps at the conversion (`addStitch(at: StagePoint(x: .infinity, y: 0))` crashes). The interpreter cannot mint ∞ via `pow` overflow — per-node normalization caps it at `Double.greatestFiniteMagnitude` (ADR-017, corrected 2026-07-19) — but that extreme *finite* coordinate flowing through `placeAt` + `stitch` still exceeds the ×2 `Int` conversion range, and non-finite `StagePoint`s remain reachable through the public engine API directly. — **Done at both**: `init(converting:)` is failable via `Int(exactly:)` (one expression, no hand-maintained bound), and `EmbroideryStream.append` no-ops on it. Guarded no-op, not clamp, per ADR-014's precedent. **The "single call seam" premise was wrong** — see the correction under the test plan.
- [x] The interpreter inherits the safety for free: an adversarial program reaching the manager with extreme coordinates leaves the stream valid and the program running — no `fatalError`, no `Int(_:)` trap. — Pinned by `extremeCoordinatesDoNotCrashTheRun`: `placeAt(5e18, 5e18)` + `stitch` still emits its `.stitch` event (the interpreter does not decide what is machine-representable), the engine drops it, the later ordinary stitch lands, and the run completes.
- [x] The guard is not over-eager: ordinary >121-unit moves still interpolate per ADR-012, and the ADR-015 ==121 layer-switch behavior is untouched. — Plus three tighter probes: a single stitch at 4.6e18 still lands (there is nothing to interpolate from), a 121 000-unit move still interpolates, and the mirror-disagreement case is a regression guard that was green before the change as well as after.

### Added beyond the ACs
- [x] **A third trap, created by this story's own bound.** Once coordinates near the `Int` conversion limit are *accepted* (which AC 4 requires), a distant second stitch gives `splitCount ≈ 7.6e16` and `addInterpolatedStitches` appends jump stitches until it exhausts memory. Swift does not trap on that, but an unbounded emission is no better for a caller than the crash this story closes. Bounded at 1 000 000 splits — ADR-014's `maxStitchesPerUpdate` number, for its reason. Running the cap *first* is also what keeps the interpolation arithmetic inside `Int`.
- [x] **The recursion is the termination argument, and it is now pinned.** Each emitted hop re-enters `append` and re-checks itself, so a hop the intermediate rounding pushes back over 121 splits again. `longButSplittableMoveStillInterpolates` makes it visible: of the 999 hops in a 121 000-unit move, 500 re-split, and the stitch count is 2503 rather than the naive 1003.

## Test-first plan
1. Journal repro at the stream level: previous x = 0.125, target x = 60.75 (decision distance 121, encoded delta 122) → no trap; the pinned semantics hold; the mirrored negative-half case likewise. — **Done, with a correction: 0.125 → 60.75 has no trapping mirror.** `javaRound`'s asymmetry means 0 → ±60.75 traps in *neither* direction, so mirroring a trapping case is not automatic. The three cases pinned are the journal's 0.125 → 60.75, the original 2026-07-09 repro −0.3 → 60.3, and its genuine negative-direction mirror 0.3 → −60.3.
2. Direct `EmbroideryStream.addStitch` at |stage| > `Int.max`/2 (e.g. 5e18) and at non-finite coordinates (`StagePoint(x: .infinity, y: 0)`, NaN) → conversion guard fires, no trap, stream stays valid. Same coordinates via `EmbroideryPatternManager.addStitch` **followed by `assembled()`** — the manager stores stage-space ops and converts only during the assembly replay, so the test must assemble to reach the chokepoint. — **Done, and the parenthetical is wrong**: the manager has *two* reach points, not one. Positions convert in the `assembled()` replay, but the clause distance (`getMaxDistanceBetweenPoints`, clauses B/C/D) converts a stage *difference* at command time, so a second `addStitch` reaches a conversion before assembly ever runs. The manager test drives both.
3. Interpreter-level smoke test through a path that actually reaches conversion (pattern moves are suppressed earlier by the ADR-014 `maxStitchesPerUpdate` guard): `placeAt(5e18, 5e18)` followed by a `stitch` brick **and `assembledStream()`** → guarded, program continues. — Done as written.
4. Not-over-eager: a legal near-boundary conversion (just under `Int.max`/2) still stitches; an ordinary long move still interpolates; the ADR-015 ==121 tie-off tests stay green. — Done as written.

## References
- `docs/workflow-journal.md` 2026-07-13 / 2026-07-14 / 2026-07-16 (carry-forward with minimal repro: decision rounds 121, positions round 0→122)
- `EmbroideryEngine`: `EmbroideryStream.swift` (interpolation decision), `DSTStitchRecord.swift` (delta from rounded positions), `DSTFile.swift` (documented known trap), `Geometry.swift` (`EmbroideryPoint(converting:)`)
- ADR-012 (interpolation), ADR-014 (finiteness guards), ADR-015 (±121 boundary) in `docs/DECISIONS.md`
- **ADR-020** (this story's outcome) in `docs/DECISIONS.md`

## Outcome

349 tests green (334 before), `swiftlint --strict` clean, CI green. Production changes in
four engine files; `DSTStitchRecord` itself is untouched.

**The red baseline is worth keeping in view.** All three trap sites reproduced, and two of
them killed the test process rather than failing an expectation: `Fatal error: Double value
cannot be converted to Int because it is either infinite or NaN` and `… because the result
would be greater than Int.max`. The ±121 cases failed cleanly instead, because `addStitch`
does not encode — the streams simply came out as two stitches with an unencodable delta
between them. That asymmetry is why `InterpolationTests`' clean-failure guard exists and why
the new suite reuses it.

**What the maximum-of-two-measures rule buys, stated narrowly.** It closes the trap without
moving a single byte at any magnitude a real design reaches, and the evidence is the goldens
being green *untouched* rather than re-blessed. What it does not buy is byte parity with
Android at the boundary itself: Catroid emits a corrupt record there and we emit a correct
split, deliberately, under ADR-012's do-not-port rule. A Catroweb round-trip landing exactly
on a half-unit ±121 boundary would therefore differ — the same class of accepted divergence
as ADR-014's and ADR-017's, and vanishingly rare for the same reason.

**Two premises in the story text turned out to be wrong**, both recorded above rather than
quietly worked around: the manager converts at command time as well as during assembly (so
the chokepoint has two reach points on that path), and the journal repro has no trapping
mirror, because `javaRound`'s negative-half asymmetry does not preserve trapping under
negation. The second is the same asymmetry ADR-015 pinned for the clause distances; it keeps
producing surprises in exactly this shape.

**Left open, deliberately, and now the next reachable crash on this path.**
`DSTHeader.appendField` preconditions each +X/−X/+Y/−Y extent into a 4-character field, so a
design wider than 9999 units traps when `DSTFile` is built — reachable at stage x = 6000,
which is far more ordinary than anything this story guards. It is a header field-width
question with its own open semantics (clamp and emit a wrong header, make `DSTFile.init`
failable and ripple that to the M3 export path, or surface "design too large" in the UI), and
that decision belongs with the export story rather than inside a coordinate-conversion
chokepoint. Carried in the journal and in ADR-020's Consequences.

**Manual Ink/Stitch verification: not needed.** No design's bytes change — the two US-106
fixtures and US-209's committed `square.dst` all compare byte-identical with the goldens
untouched, which is the check that would have caught it if any had. No new DST file is
produced by this story.
