# US-407 — The script list: rows, indentation, one VoiceOver element

**Epic**: E5 Block editor | **Estimate**: ~5 h | **Depends on**: US-401, US-405

**Story**: As a user, I want to see my program as a list of bricks with its loops visibly nested, so I can read what I have built.

The first M4 story with pixels. It is **read-only**: no reorder, no delete, no add, no parameter editing. Those are US-408/409/410, and each of them is easier for arriving at a list that already exists and is already accessible.

`swift-ui-design` pass before implementation, per CLAUDE.md's M3-onwards rule.

## Acceptance criteria

- [ ] A `List` of the working program's first script, one row per brick, indented by US-401's `Script.indentDepths`. A `loopEnd` renders at its **opener's** depth and reads as the end of that loop rather than as an anonymous row.
- [ ] `BrickRowPresentation` produces each row's text from `BrickKind` plus the brick's parameter values, **entirely from the String Catalog** with translator comments. A brick label is a sentence with values interpolated into it, which is precisely the case where word order differs by language — so the strings must be formatted, not concatenated.
- [ ] **Each row is a single VoiceOver element** whose label includes the brick's name *and* its parameter values, per the ROADMAP's M4 wording (`.accessibilityElement(children: .combine)`). Its nesting depth is conveyed too — a user who cannot see the indentation still needs to know a brick is inside a loop.
- [ ] Rows are ≥ 44 pt and reflow rather than truncate at AX1. A brick label carrying two parameters is the longest string in the app so far; indentation makes it worse by narrowing the row.
- [ ] **Every `Formula` case renders as readable text** rather than as a placeholder — `.number`, `.variable`, `.binary` (e.g. `360 ÷ Inner Loop`) **and `.unaryMinus`**, which is the fourth shipped case and which the first draft omitted *(Codex round 1)*. `OctagonRosette` ships two `.binary` nodes, so this is on screen the first time anyone opens that sample. The renderer switches exhaustively over `Formula` with no `default:`, so a fifth case would be a compile error. Rendering is this story's; which of them are *editable* is US-410's.
- [ ] Where the editor lives in the ADR-010 layout is settled here: compact and regular both, with the stage. Settling it now rather than in US-409 means the palette has somewhere defined to present from.
- [ ] Empty state: a blank program shows an invitation to add a brick, not a blank rectangle. It is the first thing a new user sees, and after US-405 it is the *default* state.
- [ ] **Story-specific definition of done**: screenshots at compact and regular, at AX1, in dark mode, and of the empty state. Thread colours in any swatch are design data and must not adapt to dark mode (M3 definition of done).

## Test-first plan

1. One row per brick, in script order, for a program with a nested loop.
2. `indentDepths` drives the rendered indentation — asserted through the presentation value, not by inspecting a view.
3. Every row's accessibility label is non-empty, localised, and contains the brick's name and each of its parameter values.
4. A loop opener's label conveys "repeat 10 times"; its `loopEnd`'s conveys the end of that loop rather than a bare word.
5. A row's label conveys its nesting depth for a brick inside a loop.
6. All four `Formula` cases render to their expected strings: `.number`, `.variable`, `.binary` nesting correctly for `360 ÷ Inner Loop`, and `.unaryMinus` (including `-(a + b)`, where dropping the parentheses would change the meaning).
7. **Every `BrickKind`** — driven from `BrickKind.allCases` via US-401's `template()` — produces a non-empty localised label. This is the coverage guard; the samples cannot be, because neither contains `forever`, `wait`, `placeAt` or `setX`, so a renderer returning an empty label for `.wait` would pass a samples-only test *(Codex round 2)*.
7b. Both shipped samples additionally produce a full set of non-empty labels — kept as a smoke test over realistic input, not as the coverage claim.
8. The empty program yields zero rows and the empty state.

## Watch items

- **Index identity is being relied on here** (ADR-034). This story must not put an interactive control inside a row. If it turns out to need one, that is the named symptom that forces an identity sidecar, and it is a reason to redesign the row rather than to add the control quietly.
- US-315 is scheduled two stories later for a transient that appears while a view's frame animates. This list will animate — expect it, and if something is seen here, record it there rather than in a review comment.

## References

- ADR-034 (index identity and what buys it), ADR-039 (reserved — this story and US-409 write it), ADR-010 (size-class adaptive layout), ADR-008 (nesting is a rendering concern — this story is where that sentence finally cashes out)
- ROADMAP M4 — "each brick is a single VoiceOver element with parameter values in its label; brick layout reflows under Dynamic Type"
- `Catroid/.../BrickAdapter.kt:113-121` — the flattening the reference renders from; ours is `indentDepths` over a list that is already flat
