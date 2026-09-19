# US-410 — Type-specific parameter editing, off-row

**Epic**: E5 Block editor | **Estimate**: ~5 h | **Depends on**: US-403, US-404, US-407

**Story**: As a user, I want to tap a brick and change its numbers and colours with a control that suits the value, so I do not need to learn a formula language to move ten steps.

`swift-ui-design` pass before implementation.

## Off-row, and it is one decision that pays three times

Tapping a row presents a small editor — sheet on compact, popover on regular — rather than putting controls in the row (ADR-039). That single choice resolves three otherwise-separate problems:

- **Identity**: no per-row focus state, so ADR-034's index identity stays honest. Putting a `TextField` in a row is the named symptom that would force an identity sidecar.
- **Accessibility**: the row stays one combined VoiceOver element with values in its label, as the ROADMAP requires. An interactive control inside a combined element is unreachable.
- **Coalescing**: the presentation's lifetime **is** the US-403 undo session, so twenty stepper taps are one undo entry with no timer anywhere.

## The problem this story cannot solve, and must therefore state

**M4 has a number pad; the model has a formula tree.** The ROADMAP defers the Catroid-style formula keyboard to M6, deliberately — "don't build editor surface for functions the M2 interpreter doesn't have". But the M2 model already holds expressions, and **a shipping sample already contains them**: `OctagonRosette` has `.repeatLoop(times: .variable("Outer Loop"))` and `.turnRight(.binary(.divide, .number(360), .variable("Inner Loop")))` — 14 non-literal formula nodes across the two samples. So this is reachable on the first tap by an ordinary curious user, not by an adversary.

**The rule (decided at planning, 2026-09-19): editable where M4 has a control, read-only where it does not.** `.number` gets the number pad; `.variable` gets the variable menu; `.binary` is **rendered as text and cannot be edited**, with a stated reason, until M6. The alternative — seed the pad and overwrite — silently destroys a working sample the first time someone taps it, and "undo can fix it" is not an answer for a loss the user did not know they were causing.

Neither reference helps: Catroid routes **every** number through the full formula editor (`FormulaBrick.java:152-164`; `content/strategy/` holds exactly three non-formula editors), and Catty does the same. The simple numeric path is our divergence, and this is its cost.

## Acceptance criteria

- [ ] Tapping a row presents a parameter editor for that brick: sheet on compact, popover on regular, one call site, presentation state hoisted above `RootView` (ADR-023's container swap).
- [ ] **Number pad** for `.number` parameters, going through US-404's `FormulaLiteral.parse`, which **rejects non-finite input** with a readable reason. `1e400` and a 310-digit entry both produce `+∞` through `Double(String)` and would then break autosave — this is where that is stopped.
- [ ] **Variable menu** listing `Object.variables + Program.variables`, honouring the documented scope rule (object shadows project, first match by name wins). **`Variable.swift:2-3` says name uniqueness within a scope "is enforced by the editor/interpreter, not the model"** — M4 is the first editor, so this story inherits that obligation and must not let the menu or a rename create a duplicate name within one scope.
- [ ] **A curated thread palette** for `setThreadColor(hex:)` — a fixed set of spool-like hex values, not the system `ColorPicker`. Three reasons, recorded in ADR-040: colour stays a **discrete** edit so there is nothing to coalesce; `ColorPicker` yields a SwiftUI `Color` and the model needs a hex string, and the `Color`→display-P3→hex round-trip is lossy and would feed ADR-015's parser values it has never seen; and DST carries **no colour at all** (US-312), so a fixed palette is the honest UI for a display-only attribute. The ROADMAP already permits "color picker **/ curated thread palette**".
- [ ] **Text fields** for `setVariable(name:)` and `writeEmbroideryToFile(name:)`.
- [ ] **A `.binary` parameter is shown rendered and is not editable**, with a visible, localised reason rather than a dead control. A disabled field with no explanation reads as a bug.
- [ ] Every change goes through `EditAction.replaceBrick`, which is **guarded to the same `BrickKind`** (ADR-035) — so a parameter edit can never orphan a `loopEnd`.
- [ ] **One undo entry per editing session**, not per keystroke or per stepper tap. `endEdit()` is idempotent, and it is also called from the view model's own reset path, because ADR-023's container swap can dismiss the sheet without it firing — a stale session key would swallow the next unrelated edit's undo entry.
- [ ] **Story-specific definition of done**: screenshots of each editor type, the read-only `.binary` state, and the thread palette in dark mode — where the swatches must **not** adapt, being design data.

## Test-first plan

1. Each parameter kind maps to its expected editor type, driven by `BrickKind` and the payload.
2. Committing a number produces exactly one `replaceBrick` with the expected whole `Brick`.
3. `FormulaLiteral.parse` rejection surfaces in the editor rather than committing — asserted for `1e400` and for the 310-digit string.
4. Twenty stepper increments inside one session produce **one** undo entry, and undoing returns the value that was there when the editor opened.
5. Two sessions produce two entries.
6. A session dismissed without an explicit `endEdit()` does not coalesce the *next* edit into itself — the container-swap regression test.
7. The variable menu lists object variables before project variables and resolves a shadowed name to the object's.
8. A thread-palette choice produces `replaceBrick` with the exact hex string, unchanged by any colour round-trip.
9. A `.binary` parameter's editor is non-editable and exposes a non-empty localised reason.
10. `replaceBrick` with a different kind never occurs from this UI — asserted at the view-model boundary, since ADR-035 already rejects it in the funnel.

**Mutation targets**: a session keyed on the brick's *value* rather than its address plus token (green while values differ, coalescing wrongly when a user sets a value back); the palette committing a normalised or lowercased hex that does not match the constant.

## References

- ADR-039 (off-row presentation), ADR-040 (reserved — this story writes the curated palette), ADR-035 (same-kind `replaceBrick`), ADR-034 (why no control goes in a row), ADR-023 (the container swap)
- ADR-015 — thread-colour semantics, including invalid-hex no-op, which the palette must not start exercising
- US-404 — `FormulaLiteral.parse`; US-312 — why colour is display-only
- `Catroid/.../FormulaBrick.java:152-164`, `content/strategy/` — every number through the formula editor, and the three exceptions; `Catty/.../StitchThreadColorCell.swift:22-51` — thread colour as a plain text field
