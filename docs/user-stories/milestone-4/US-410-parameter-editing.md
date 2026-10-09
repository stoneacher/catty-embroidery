# US-410 — Type-specific parameter editing, off-row

**Epic**: E5 Block editor | **Estimate**: ~5 h | **Depends on**: US-403, US-404, US-407

**Status**: Done — 2026-10-03, [PR #66](https://github.com/stoneacher/catty-embroidery/pull/66) (pending merge). Test-first in seven `[red]` slices: package, app, number-field spelling, the in-loop review round, and Codex rounds 1–3. Reviewed by `swift-code-reviewer`: 25 mutants, 10 survived, all 10 now killed by new tests, four re-run to confirm. **Four Codex rounds**: Medium → Medium → Medium → none. That is 6 findings, all valid and all fixed. The loop was escalated after round 3 at flat Medium, and Sebastian chose to run round 4, which was clean. Screenshots are in `docs/screenshots/us-410/`. The manual items below go to the bundled M4 pass.

## Decisions taken in this story (Sebastian, 2026-10-03, after `swift-architect` and `swift-ui-design` passes)

- **One story, not split**, although the architect estimated it at 9–10 h.
- **Declare on use, through a sixth `EditAction`**: `declareVariable(name:script:)`, at object scope. This is ADR-035's 2026-10-03 amendment. It amends US-402's five cases and US-411's totality fixtures; both stories carry a note.
- **Names that imitate the display syntax: restrict the characters.** The rules are in `VariableName` and ADR-040:
  - no quotation mark of any script;
  - no opening punctuation first;
  - no control or invisible format characters (the review round added format characters);
  - nothing empty, and no surrounding whitespace.

  **File names are not restricted.** A file named `(empty)` is a known, accepted look-alike, because forbidding parentheses in file names would be hostile. The editor never writes an empty file name.
- **Live-apply inside one coalescing session.** The exceptions:
  - Variable names commit on Create or a menu choice, never per keystroke.
  - A rejected number entry returns the slot to where the typing run began. This was found on the simulator: typing `1e400` committed `1e40` on the way.
- **Smaller defaults, recorded rather than asked:**
  - The editor opens from the selected row: an Edit button in the bottom bar, and an "Edit Parameters" accessibility action (ADR-039's 2026-10-03 amendment).
  - Every `.unaryMinus` is read-only, `.unaryMinus(.number(5))` included.
  - A thread colour that is not a swatch shows as "Current Colour", untouched.
  - The sheet is modal: background interaction is off.
  - Number entry accepts both the locale's separator and `.`.
  - The stepper moves by ±1.

**Story**: As a user, I want to tap a brick and change its numbers and colours with a control that suits the value, so I do not need to learn a formula language to move ten steps.

`swift-ui-design` pass before implementation.

## Off-row, and it is one decision that pays three times

Tapping a row presents a small editor — sheet on compact, popover on regular — rather than putting controls in the row (ADR-039). That single choice resolves three otherwise-separate problems:

- **Identity**: no per-row focus state, so ADR-034's index identity stays honest. Putting a `TextField` in a row is the named symptom that would force an identity sidecar.
- **Accessibility**: the row stays one combined VoiceOver element with values in its label, as the ROADMAP requires. An interactive control inside a combined element is unreachable.
- **Coalescing**: the presentation's lifetime **is** the US-403 undo session, so twenty stepper taps are one undo entry with no timer anywhere.

## The problem this story cannot solve, and must therefore state

**M4 has a number pad; the model has a formula tree.** The ROADMAP defers the Catroid-style formula keyboard to M6, deliberately — "don't build editor surface for functions the M2 interpreter doesn't have". But the M2 model already holds expressions, and **a shipping sample already contains them**: `OctagonRosette` has `.repeatLoop(times:.variable("Outer Loop"))` and `.turnRight(.binary(.divide,.number(360),.variable("Inner Loop")))`. Counted from the checked-in JSON: **8 non-literal `Formula` nodes across 6 brick parameters** — Rosette 6 in 4 (2 `.binary`, 4 `.variable`), Coil 2 `.variable` in 2, because `coilLoop` is a helper called twice (`SquareCoilProgram.swift:64`, `:71`). So this is reachable on the first tap by an ordinary curious user, not by an adversary.

**The rule (decided at planning, 2026-09-19): editable where M4 has a control, read-only where it does not.** `.number` gets the number pad; `.variable` gets the variable menu; **`.binary` and `.unaryMinus`** are **rendered as text and cannot be edited**, with a stated reason, until M6. A persisted `.moveNSteps(.unaryMinus(.variable("Side")))` must have a specified treatment too. The read-only path must **preserve the tree**, not replace it with an evaluated literal. The alternative — seed the pad and overwrite — silently destroys a working sample the first time someone taps it, and "undo can fix it" is not an answer for a loss the user did not know they were causing.

Neither reference helps: Catroid routes **every** number through the full formula editor (`FormulaBrick.java:152-164`; `content/strategy/` holds exactly three non-formula editors), and Catty does the same. The simple numeric path is our divergence, and this is its cost.

## Acceptance criteria

- [x] Tapping a row presents a parameter editor for that brick: sheet on compact, popover on regular, one call site, presentation state hoisted above `RootView` (ADR-023's container swap).
- [x] **Number pad** for `.number` parameters, going through US-404's `FormulaLiteral.parse`, which **rejects non-finite input** with a readable reason. `1e400` and a 310-digit entry both produce `+∞` through `Double(String)` and would then break autosave — this is where that is stopped.
- [x] **Variable menu** listing `Object.variables + Program.variables`, honouring the documented scope rule (object shadows project, first match by name wins). **`Variable.swift:2-3` says name uniqueness within a scope "is enforced by the editor/interpreter, not the model"** — M4 is the first editor, so this story inherits that obligation and must not let the menu or a rename create a duplicate name within one scope.
- [x] **There must be a way for the menu to be non-empty**, and the plan did not have one. Concrete workflow that fails: start from the blank program, add `setVariable(name: "Side", to: 9)`, add `moveNSteps(10)`, and try to make it use `Side`. The menu reads `Object.variables + Program.variables`; **none of the five `EditAction` cases declares a variable there**, and running the program does not help — `setVariable` creates an independent *runtime* entry (`Interpreter+Step.swift:263`). From a blank program the menu is empty forever, so the new control/data palette cannot express a variable-driven design at all. Resolve it in one of two ways, and say which: **declare on use** (editing a `setVariable`/`changeVariableBy` name adds the declaration to `Object.variables`, which needs a sixth `EditAction` case or an extension of `replaceBrick`'s effect), or a small **manage-variables** affordance. Whichever is chosen is an ADR-035 amendment, because it changes what an `EditAction` may do.
- [x] **A `.number` parameter can be switched to a `.variable` one and back.** Otherwise a brick authored with a literal can never reference a variable, and the menu is unreachable even once it is populated. The editor for a numeric parameter offers both, and the switch is one `replaceBrick`.
- [x] **Text fields cover `changeVariableBy(name:)` as well as `setVariable(name:)`.**
- [x] **A curated thread palette** for `setThreadColor(hex:)` — a fixed set of spool-like hex values, not the system `ColorPicker`. Three reasons, recorded in ADR-040: colour stays a **discrete** edit so there is nothing to coalesce; `ColorPicker` yields a SwiftUI `Color` and the model needs a hex string, and the `Color`→display-P3→hex round-trip is lossy and would feed ADR-015's parser values it has never seen; and DST carries **no colour at all** (US-312), so a fixed palette is the honest UI for a display-only attribute. The ROADMAP already permits "color picker **/ curated thread palette**".
- [x] **Text fields** for `writeEmbroideryToFile(name:)`.
- [x] **A `.binary` or `.unaryMinus` parameter is shown rendered and is not editable**, with a visible, localised reason rather than a dead control. A disabled field with no explanation reads as a bug. Leaving the editor must leave the formula tree **byte-identical** — no round-trip through a displayed string.
- [x] Every **parameter** change goes through `EditAction.replaceBrick`, which is **guarded to the same `BrickKind`** (ADR-035) — so a parameter edit can never orphan a `loopEnd`. The qualifier matters: a declaration made through a manage-variables affordance has no brick to replace. A **variable declaration** is not a parameter change: it goes through whichever mechanism that criterion settles on, and it still goes through the `apply` funnel — no view writes `Object.variables` directly, which ADR-006 pattern 1 forbids. If the chosen mechanism is a sixth `EditAction` case, **US-402's five-case set and US-411's totality fixtures are amended by this story**, and the amendment is named in both.
- [x] **One undo entry per editing session**, not per keystroke or per stepper tap. `endEdit()` is idempotent, and it is also called from the view model's own reset path, because ADR-023's container swap can dismiss the sheet without it firing — a stale session key would swallow the next unrelated edit's undo entry.
- [x] **Story-specific definition of done**: screenshots of each editor type, the read-only `.binary` state, and the thread palette in dark mode — where the swatches must **not** adapt, being design data.

**Definition-of-done screenshots** (`docs/screenshots/us-410/`, iPhone 17, simulator locale with a decimal comma):
- `01` the number slot;
- `02` the `1e400` rejection (taken before the prefix fix, which is how the defect was found);
- `03a` a variable reference;
- `04` a `setVariable` target;
- `05`/`06` the thread palette in light and dark mode, where the swatches do not adapt;
- `07` Octagon Rosette's read-only `360 ÷ "Inner Loop"`.

**Not captured, and left for the bundled M4 manual pass:**
- the variable menu opened (the automation tap does not open SwiftUI menus);
- the iPad popover;
- VoiceOver reading the swatch names and the `.isSelected` trait;
- whether the row action opens the editor while another presentation is dismissing (the action is withheld while the palette is up).

## Test-first plan

1. Each parameter kind maps to its expected editor type, driven by `BrickKind` and the payload.
2. Committing a number produces exactly one `replaceBrick` with the expected whole `Brick`.
3. `FormulaLiteral.parse` rejection surfaces in the editor rather than committing — asserted for `1e400` and for the 310-digit string.
4. Twenty stepper increments inside one session produce **one** undo entry, and undoing returns the value that was there when the editor opened.
5. Two sessions produce two entries.
6. A session dismissed without an explicit `endEdit()` does not coalesce the *next* edit into itself — the container-swap regression test.
7. The variable menu lists object variables before project variables and resolves a shadowed name to the object's.
7b. **The blank-program workflow**: from the blank program, author a variable, then reference it from a `moveNSteps` — the menu offers it and the resulting whole `Program` is as expected. The test that fails against an edit-only rule.
7c. Switching a `.number` parameter to `.variable` and back produces the expected whole `Brick` each way, through `replaceBrick`.
8. A thread-palette choice produces `replaceBrick` with the exact hex string, unchanged by any colour round-trip.
9. A `.binary` parameter's editor is non-editable and exposes a non-empty localised reason; likewise `.unaryMinus`. Opening and dismissing either leaves the whole `Program` unchanged.
10. `replaceBrick` with a different kind never occurs from this UI — asserted at the view-model boundary, since ADR-035 already rejects it in the funnel.

## Inherited from US-407 (Codex round 2, 2026-09-28): names that imitate the display syntax

US-407 renders a variable inside a formula as `"name"` (the `formula.variable` catalog format, which is Catroid's convention). It renders an empty name or string as a placeholder: `(no variable)` for a variable, `(empty)` for a file name or colour. Two inputs still defeat that, and both are free text that this story is the first to let a user create:
- **A name containing the quotation mark**: `.variable("a\" + \"b") × c` renders `"a" + "b" × "c"`, which reads as a sum.
- **A name spelled like a placeholder**: a variable named `(no variable)` reads the same as an unset one. A file named `(empty)` reads the same as an empty file name.

They were deliberately left out of US-407. No UI there creates names, and escaping ASCII `"` would be wrong in every language whose translator picked other quotation marks. Decide here, where names are created: restrict the characters a name may hold, escape against the localized delimiters, or render the placeholders so that no name can collide with them.

## References

- ADR-039 (off-row presentation), ADR-040 (reserved — this story writes the curated palette), ADR-035 (same-kind `replaceBrick`), ADR-034 (why no control goes in a row), ADR-023 (the container swap)
- ADR-015 — thread-colour semantics, including invalid-hex no-op, which the palette must not start exercising
- US-404 — `FormulaLiteral.parse`; US-312 — why colour is display-only
- `Catroid/.../FormulaBrick.java:152-164`, `content/strategy/` — every number through the formula editor, and the three exceptions; `Catty/.../StitchThreadColorCell.swift:22-51` — thread colour as a plain text field
