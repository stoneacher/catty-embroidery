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

**M4 has a number pad; the model has a formula tree.** The ROADMAP defers the Catroid-style formula keyboard to M6, deliberately — "don't build editor surface for functions the M2 interpreter doesn't have". But the M2 model already holds expressions, and **a shipping sample already contains them**: `OctagonRosette` has `.repeatLoop(times: .variable("Outer Loop"))` and `.turnRight(.binary(.divide, .number(360), .variable("Inner Loop")))`. Counted from the checked-in JSON: **8 non-literal `Formula` nodes across 6 brick parameters** — Rosette 6 in 4 (2 `.binary`, 4 `.variable`), Coil 2 `.variable` in 2, because `coilLoop` is a helper called twice (`SquareCoilProgram.swift:64`, `:71`). So this is reachable on the first tap by an ordinary curious user, not by an adversary.

**The rule (decided at planning, 2026-09-19): editable where M4 has a control, read-only where it does not.** `.number` gets the number pad; `.variable` gets the variable menu; **`.binary` and `.unaryMinus`** are **rendered as text and cannot be edited**, with a stated reason, until M6. *(Codex round 1: the first draft named only `.binary` and silently omitted `.unaryMinus`, the fourth shipped `Formula` case — a persisted `.moveNSteps(.unaryMinus(.variable("Side")))` would have had no specified treatment at all.)* The read-only path must **preserve the tree**, not replace it with an evaluated literal. The alternative — seed the pad and overwrite — silently destroys a working sample the first time someone taps it, and "undo can fix it" is not an answer for a loss the user did not know they were causing.

Neither reference helps: Catroid routes **every** number through the full formula editor (`FormulaBrick.java:152-164`; `content/strategy/` holds exactly three non-formula editors), and Catty does the same. The simple numeric path is our divergence, and this is its cost.

## Acceptance criteria

- [ ] Tapping a row presents a parameter editor for that brick: sheet on compact, popover on regular, one call site, presentation state hoisted above `RootView` (ADR-023's container swap).
- [ ] **Number pad** for `.number` parameters, going through US-404's `FormulaLiteral.parse`, which **rejects non-finite input** with a readable reason. `1e400` and a 310-digit entry both produce `+∞` through `Double(String)` and would then break autosave — this is where that is stopped.
- [ ] **Variable menu** listing `Object.variables + Program.variables`, honouring the documented scope rule (object shadows project, first match by name wins). **`Variable.swift:2-3` says name uniqueness within a scope "is enforced by the editor/interpreter, not the model"** — M4 is the first editor, so this story inherits that obligation and must not let the menu or a rename create a duplicate name within one scope.
- [ ] **There must be a way for the menu to be non-empty**, and the plan did not have one *(Codex round 2, and it is a functional gap rather than a wording problem)*. Concrete workflow that fails: start from the blank program, add `setVariable(name: "Side", to: 9)`, add `moveNSteps(10)`, and try to make it use `Side`. The menu reads `Object.variables + Program.variables`; **none of the five `EditAction` cases declares a variable there**, and running the program does not help — `setVariable` creates an independent *runtime* entry (`Interpreter+Step.swift:263`). From a blank program the menu is empty forever, so the new control/data palette cannot express a variable-driven design at all. Resolve it in one of two ways, and say which: **declare on use** (editing a `setVariable`/`changeVariableBy` name adds the declaration to `Object.variables`, which needs a sixth `EditAction` case or an extension of `replaceBrick`'s effect), or a small **manage-variables** affordance. Whichever is chosen is an ADR-035 amendment, because it changes what an `EditAction` may do.
- [ ] **A `.number` parameter can be switched to a `.variable` one and back.** Otherwise a brick authored with a literal can never reference a variable, and the menu is unreachable even once it is populated. The editor for a numeric parameter offers both, and the switch is one `replaceBrick`.
- [ ] **Text fields cover `changeVariableBy(name:)` as well as `setVariable(name:)`** — the first draft omitted it.
- [ ] **A curated thread palette** for `setThreadColor(hex:)` — a fixed set of spool-like hex values, not the system `ColorPicker`. Three reasons, recorded in ADR-040: colour stays a **discrete** edit so there is nothing to coalesce; `ColorPicker` yields a SwiftUI `Color` and the model needs a hex string, and the `Color`→display-P3→hex round-trip is lossy and would feed ADR-015's parser values it has never seen; and DST carries **no colour at all** (US-312), so a fixed palette is the honest UI for a display-only attribute. The ROADMAP already permits "color picker **/ curated thread palette**".
- [ ] **Text fields** for `writeEmbroideryToFile(name:)`.
- [ ] **A `.binary` or `.unaryMinus` parameter is shown rendered and is not editable**, with a visible, localised reason rather than a dead control. A disabled field with no explanation reads as a bug. Leaving the editor must leave the formula tree **byte-identical** — no round-trip through a displayed string.
- [ ] Every **parameter** change goes through `EditAction.replaceBrick`, which is **guarded to the same `BrickKind`** (ADR-035) — so a parameter edit can never orphan a `loopEnd`. *(Qualified at Codex round 3: the unconditional "every change" contradicted the variable-declaration criterion above, which by construction has no brick to replace when it comes from a manage-variables affordance.)* A **variable declaration** is not a parameter change: it goes through whichever mechanism that criterion settles on, and it still goes through the `apply` funnel — no view writes `Object.variables` directly, which ADR-006 pattern 1 forbids. If the chosen mechanism is a sixth `EditAction` case, **US-402's five-case set and US-411's totality fixtures are amended by this story**, and the amendment is named in both.
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
7b. **The blank-program workflow**: from the blank program, author a variable, then reference it from a `moveNSteps` — the menu offers it and the resulting whole `Program` is as expected. The test that fails against the first draft's design.
7c. Switching a `.number` parameter to `.variable` and back produces the expected whole `Brick` each way, through `replaceBrick`.
8. A thread-palette choice produces `replaceBrick` with the exact hex string, unchanged by any colour round-trip.
9. A `.binary` parameter's editor is non-editable and exposes a non-empty localised reason; likewise `.unaryMinus`. Opening and dismissing either leaves the whole `Program` unchanged.
10. `replaceBrick` with a different kind never occurs from this UI — asserted at the view-model boundary, since ADR-035 already rejects it in the funnel.

**Mutation targets**: the palette committing a normalised or lowercased hex that does not match the constant; and `endEdit()` implemented as a no-op, which is green for tests 4 and 5 and caught only by test 6. *(The first draft named a value-keyed session as a mutation that "stays green while values differ" — **false**: under US-403's top-key-equality rule twenty successive values give twenty distinct keys and twenty undo entries, so test 4 fails immediately. Codex round 4; the third false mutation prediction in this plan.)*

## References

- ADR-039 (off-row presentation), ADR-040 (reserved — this story writes the curated palette), ADR-035 (same-kind `replaceBrick`), ADR-034 (why no control goes in a row), ADR-023 (the container swap)
- ADR-015 — thread-colour semantics, including invalid-hex no-op, which the palette must not start exercising
- US-404 — `FormulaLiteral.parse`; US-312 — why colour is display-only
- `Catroid/.../FormulaBrick.java:152-164`, `content/strategy/` — every number through the formula editor, and the three exceptions; `Catty/.../StitchThreadColorCell.swift:22-51` — thread colour as a plain text field
