# Backlog — specified but not yet scheduled

Stories that are fully analysed but have no milestone yet. They live here rather than in a
milestone folder so a closed milestone's "all N stories merged" claim stays true, and so the
analysis is captured while it is fresh instead of being re-derived at the next planning
session. Precedent for why that matters: the ±121 coordinate trap sat as a journal
carry-forward from 2026-07-09 to M2 planning, and was then mis-scoped twice by review before
it became US-210.

Milestone planning picks these up and assigns them a place; the ID stays stable so existing
ADR and journal references keep resolving.

---

## US-211 — DST serialization field-width chokepoint

**Epic**: E2 Embroidery engine (semantics shared with E7 Export) | **Estimate**: ~3 h | **Depends on**: US-210 (ADR-020)

**Status**: Specified 2026-07-31, unscheduled. Candidate for M3, where the export path forces the decision this story needs.

**Story**: As the DST writer, I want the header's fixed-width fields to stop being a
`precondition` on ordinary input, so that a design larger than the Tajima header can express
fails in a way a caller can handle instead of killing the process.

`DSTHeader.appendField` ends with `precondition(valueBytes.count <= width, …)`. Every field is
a fixed width, so a value that does not fit is a crash — and two of them are reachable from
coordinates and colour counts a real design can produce. US-210 closed the *coordinate*
chokepoint (ADR-020) and deliberately left this one open: a header field cannot be a guarded
no-op the way a stitch can, so the fix is a different decision, not a wider version of the
same one.

### The reachable fields

Verified by execution (exit tests, 2026-07-31) unless marked otherwise:

| Field | Width | Overflows at | Reachable how |
|---|---|---|---|
| `+X` / `−X` / `+Y` / `−Y` | 4 | extent > 9999 units | **Confirmed crash**: `addStitch(0,0)` then `addStitch(6000,0)` → `+X` = 12000. Stage x = 6000 is 12× the ADR-007 stage, but nothing bounds a `StagePoint`. |
| `CO` | 2 | > 99 colour blocks | **Confirmed crash**: 99 `addColorChange()` calls → `CO` = 100. Well within a complex multi-colour design. |
| `ST` | 6 | > 999 999 stitches | **Derived, not executed** (needs ~10⁶ stitches): ADR-020 admits a move of up to 121 000 000 units, i.e. `splitCount` = 1 000 000, which emits at least `splitCount + 3` stitches. So a *single* move this engine now accepts by design overflows `ST`. Worth confirming first — if it holds, ADR-020's cap and this field are coupled and the cap may want to be 999 996 rather than a round million. |
| `AX` / `AY` | 5, signed | \|value\| > 9999 (negative) | Implied safe *once extents are bounded*, since `|AX| ≤ max extent`. Not an independent case. |
| `LA` | 15 | — | Already handled: `sanitized()` truncates (ADR-012). |

### Acceptance criteria
- [ ] No `StagePoint` input, however adversarial, makes `DSTFile(stream:name:)` trap. The `precondition` in `appendField` becomes unreachable-by-construction or is replaced.
- [ ] The chosen semantics are pinned as an ADR, extending ADR-020's reasoning to the serialization boundary. **The decision is the story** — the options are not equivalent:
  - **Clamp the extent** and emit a header that misdescribes the design. Cheapest, and the worst of the three: a silently wrong header is exactly the "parity with corruption" ADR-012 refuses elsewhere.
  - **Make `DSTFile.init` failable or throwing.** Honest, and the only option that lets a caller respond. Cost: it touches every golden test call site and the M3 export path, and turns a value-type initializer into an error-handling surface.
  - **Bound the design at the app layer** per ADR-007 and keep the engine's precondition as a genuine programmer-error backstop. Cheapest correct option *if* the engine is never a public API — but the engine is a standalone package and US-210's whole premise was that direct engine callers must not be crashable.
- [ ] Whatever is chosen, the ADR-020 cap interaction is resolved: either the split cap is lowered so a single admitted move cannot overflow `ST`, or the story shows why it cannot.
- [ ] Existing golden byte-identity is untouched — the two US-106 fixtures and US-209's `square.dst` stay green with no re-blessing.

### Test-first plan
1. Exit tests pinning today's behaviour first (they pass — the traps are real), then converted to the chosen semantics: extents at 10 000 units, `CO` at 100 blocks.
2. The `ST` case: confirm or refute the derived claim above with a single capped move, then pin whichever way it lands.
3. The just-inside cases stay working: extent exactly 9999, `CO` exactly 99.
4. If `DSTFile.init` becomes failable/throwing: every existing golden call site updated with `try #require`, and one test proving a caller can distinguish "too large" from any other failure.

### References
- `Packages/EmbroideryEngine/Sources/EmbroideryEngine/DSTHeader.swift` (`appendField`, the field table above)
- ADR-020 Consequences (why US-210 left this open), ADR-012 (extents relative to first stitch, magnitudes only), ADR-007 (stage bounds)
- `docs/workflow-journal.md` 2026-07-31 (US-210 rounds; the carry-forward that opened this)
