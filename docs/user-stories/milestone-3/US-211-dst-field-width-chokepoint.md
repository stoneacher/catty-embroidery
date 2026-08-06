# US-211 — DST serialization field-width chokepoint

**Epic**: E2 Embroidery engine (semantics shared with E7 Export) | **Estimate**: ~3 h | **Depends on**: US-210 (ADR-020)

**Status**: Not started. Specified 2026-07-31 at discovery time (in `backlog.md`); scheduled into M3 on 2026-08-04. **ID preserved** so the ADR-020 and journal references that already cite it keep resolving.

**Story**: As the DST writer, I want the header's fixed-width fields to stop being a `precondition` on ordinary input, so that a design larger than the Tajima header can express fails in a way a caller can handle instead of killing the process.

`DSTHeader.appendField` ends with `precondition(valueBytes.count <= width, …)`. Every field is fixed-width, so a value that does not fit is a crash — and several are reachable from coordinates and colour counts a real design can produce. US-210 closed the *coordinate* chokepoint (ADR-020) and deliberately left this one open: a header field cannot be a guarded no-op the way a stitch can, so the fix is a different decision, not a wider version of the same one.

**It is scheduled here because the export path is the caller that forces the decision** — and now that US-308's design exists, it does.

## The reachable fields

Verified by execution unless marked otherwise. Widths confirmed directly against `DSTHeader.swift:19-30`.

| Field | Width | Overflows at | Reachable how |
|---|---|---|---|
| `+X` / `−X` / `+Y` / `−Y` | 4 | extent > 9999 units | **Confirmed crash**: `addStitch(0,0)` then `addStitch(6000,0)` → `+X` = 12000. But see the asymmetry below — stage x = 6000 is 12× the ADR-007 stage. |
| `CO` | 2 | > 99 colour blocks | **Confirmed crash**: 99 `addColorChange()` calls → `CO` = 100 (width 3). Reachable by a design that never leaves the stage. |
| `ST` | 6 | > 999 999 stitches | **Confirmed by execution (2026-08-04)** — the backlog's "derived, not executed" caveat is retired. Two recipes: the ADR-020 cap move (0 → 60 500 000 stage points) yields **2 500 003** stitches, not the ~1 000 003 originally derived, because intermediates re-split; and `ST` can be isolated from `+X` with 1 000 001 stitches inside a 2-unit extent (alternate two points 1 unit apart to dodge dedup). Both run in well under 0.1 s. |
| `AX` / `AY` | 5, signed | \|value\| > 9999 (negative) | Implied safe once extents are bounded, since \|AX\| ≤ max extent. Not an independent case. |
| `LA` | 15 | — | Already handled: `sanitized()` truncates (ADR-012). |

**The reachability is asymmetric, and the ADR must say so.** Inside ADR-007's 500×500 stage the maximum extent is 1000 embroidery units — comfortably inside the 4-wide fields. So extent overflow is only reachable *outside* the documented stage, whereas `CO` and `ST` are reachable by designs that never leave it. The traps are not equally ordinary, and that asymmetry is what rules out bounding coordinates as a fix.

**The backlog's field list was incomplete**: `DSTHeader.init(stream:name:)` is **public** (`DSTHeader.swift:13`), so it is a second trapping entry point independent of `DSTFile`.

## The decision

**`DSTFile.init` and `DSTHeader.init` become `throws`.** Decided at M3 planning (2026-08-04), to be pinned as **ADR-025** at close-out. The three options were not equivalent:

- **Clamp the extent** and emit a header that misdescribes the design — rejected. ADR-012 refuses parity-with-corruption elsewhere; this would be corruption we *chose*, in the one field a machine reads to size the design, and it is undetectable downstream.
- **Bound the design at the app layer** per ADR-007 — rejected, and it fails on its own terms. ADR-007's stage bounds **do not exist as code** (`grep -rn "500" Sources/` returns two comments and no constant), so this option must first introduce engine-space bounds, moving its cost toward the throwing option rather than away. Worse, the asymmetry above means bounding coordinates would close only the trap already out of reach and leave the two that are in reach. Wrong shape for the problem.
- **Throwing, not merely failable** — chosen. It is the only option that lets a caller respond, and US-308 has a caller that must: the export path needs to tell the user *which* limit was hit ("118 colour blocks; DST allows 99"). `Optional` cannot carry that. And `DSTFile` is not gaining an error surface for the first time — `write(to:)` already throws.

**Measured cost**: **33 call sites** gain `try` — 19 × `DSTFile(stream`, 14 × `DSTHeader(stream` in checked-in Swift. In tests these become `try #require` or `throws` test functions.

(Provenance of that number, since it was got wrong once: a planning-session count of 39 came from a `grep` without `--include='*.swift'`, which swept `README.md`, `Tests/InterpreterTests/Resources/GoldenPrograms/PROVENANCE.md` and two `.build/` artifact copies. Codex round 1 caught it. Count Swift only.)

**On the ADR-020 cap (the backlog's AC 3): do not lower it.** Once `init` throws, `ST` overflow is a *handled error*, so the cap no longer needs to protect the header. Lowering 1 000 000 → 999 996 would change interpolation *emission* for moves the engine admits by design, in order to guard an error that is now representable, and would break the shared rationale ADR-014 and ADR-020 both hang on that number. Pin the opposite: `ST` overflow is a serialization error, not an interpolation bound.

## Acceptance criteria
- [ ] No `StagePoint` input, however adversarial, makes `DSTFile(stream:name:)` **or `DSTHeader(stream:name:)`** trap. `appendField`'s `precondition` becomes unreachable-by-construction, or the width check moves into the throwing path.
- [ ] Both initializers are `throws`, with a public `DSTSerializationError: Error, Equatable, Sendable` a caller can switch on to name the field, the offending value, and the limit.
- [ ] The `ST` case is confirmed by execution (both recipes above), and the ADR records that ADR-020's 1 000 000 cap **stays**, with the reasoning above.
- [ ] Just-inside cases stay working: extent exactly 9999, `CO` exactly 99, `ST` exactly 999 999.
- [ ] Existing golden byte-identity is untouched — the two US-106 fixtures and US-209's `square.dst` stay green with **no re-blessing**. If a golden needs re-blessing, the change is wrong.
- [ ] Sweep the incidental defect ADR-020 recorded but never fixed in code: `StitchPattern.swift:22-23` still says "DST's stitch-count header field itself caps at seven digits". It is width **6** (`DSTHeader.swift:20`). The 1 000 000 bound that parenthetical justifies is unaffected.
- [ ] **ADR-025 states the reachability asymmetry explicitly** — extent overflow unreachable inside ADR-007's stage, `CO` and `ST` reachable inside it — so a later reader does not "simplify" the fix back to bounding coordinates.
- [ ] ADR-019 screening: state that these inputs sit deliberately *on* field-width boundaries. That is the subject of the tests, not an accident of them.

## Test-first plan
1. **Exit tests** pinning today's traps first — `#expect(processExitsWith:)`, the mechanism US-210 already used for ADR-020 — then converted to the chosen semantics. `+X`: `addStitch(0,0)` then `addStitch(6000,0)`. `CO`: 99 `addColorChange()`. `ST`: 1 000 001 stitches inside a 2-unit extent. **These must be exit tests, not ordinary ones**: `precondition` traps, and a trap terminates the test process rather than throwing, so an in-process "characterisation test" would kill the suite instead of passing. (An earlier draft of this plan said "characterisation tests… they pass", dropping the word "exit" that the backlog specification had and losing the mechanism with it — Codex round 1.) **Note the ordering trap too**: `appendField` writes `ST` *before* `+X`, so an `ST` test built from a huge move would trap on the wrong field — isolate it with the tight-extent recipe.
2. The ADR-020 cap move confirms `ST` reaching width 7, and that cap and field are decoupled once `init` throws.
3. Just-inside boundaries stay green (9999 / 99 / 999 999).
4. All 33 call sites updated with `try` / `try #require`; one test proves a caller can distinguish "too large" — and *which* field — from any other failure.
5. The two US-106 goldens and `square.dst` re-run byte-identical.

## References
- `Packages/EmbroideryEngine/Sources/EmbroideryEngine/DSTHeader.swift` — `appendField`, the field table, the public `init`
- ADR-020 Consequences (why US-210 left this open, and the "not closed" section that spawned this story), ADR-012 (extents relative to first stitch, magnitudes only), ADR-007 (stage bounds — which exist only as prose), ADR-014 (the 1 000 000 cap's shared rationale)
- `docs/workflow-journal.md` 2026-07-31 (US-210's four Codex rounds; the carry-forward that opened this) and 2026-08-04 (the M3 planning session that scheduled it)
- ADR-025 (this story's close-out)
