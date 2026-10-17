# Brick backend

**Status**: Planned — 2026-10-17 | **Epic**: E8 (+ E3 formulas, E5 thin) | **Branch**: `feature/brick-backend`

**Goal**: a program can draw arcs and quadratic curves (Catroid's **Arc** and **GoThrough**), and its formulas can use Catroid's math functions and the object's own x, y and direction. Preview and `.dst` export behave as the Android Embroidery Designer does wherever Catroid is sound, and every divergence is pinned by a named test.

Arc and GoThrough are the only bricks of Catroid's Embroidery category still missing here (`CategoryBricksFactory.kt:1039-1056` appends `setupPeripheralMotionBrickList()`, `:1080-1094`). They join our `.motion` palette group after `pointInDirection`.

**In scope**
- `Brick.arc(direction:radius:degrees:)` and `Brick.goThrough(throughX:throughY:x:y:)`, executed, previewed and exported.
- Formula functions: `sin cos tan arcsin arccos arctan arctan2 sqrt abs round floor ceil ln log exp pi min max mod`.
- Formula sensors: `objectX objectY motionDirection`.
- Thin app wiring: palette entries, row sentences, symbols/tints, a left/right control for Arc, number fields for GoThrough, locked display of function and sensor formulas.
- One bundled sample using Arc, GoThrough and functions (decided 2026-10-17), so the feature is visible in the app and Ink/Stitch has a real design to check.

**Out of scope** (each deliberate)
- **`rand`** — deferred (decided 2026-10-17). Evaluation is pure, Catroid's integer-vs-decimal rule needs the literal's spelling (`Formula.number(Double)` drops it), and it costs byte-exact tests. Recorded design for later: a seeded generator stored inside `Interpreter`, seed injected per run.
- **Authoring functions or sensors in the UI.** There is still no formula editor (ADR-040); these formulas are shown locked with a reason. They reach a program through files, Swift-built samples and the planned language-test runner. Not a defect.
- Catroid's `power()` function (`^` exists, with ADR-017's pinned semantics), `true`/`false`, comparisons, logic, and the control bricks If/IfElse, RepeatUntil, WaitUntil, ForVariableFromTo — the **Variables** feature.
- Other sensors; GlideTo, GoTo, PointTo, IfOnEdgeBounce (not in Catroid's Embroidery category).
- The engine's `javaRound` (`Geometry.swift:16`, `floor(x + 0.5)`) differing from Java 7+ `Math.round` at 0.49999999999999994 and near 2^52: sub-resolution for coordinates (ADR-019 class), so it goes to the backlog together with a correction note on ADR-012's wording. The **ROUND function** implements Java 7+ semantics from the start.

**Brief review**: **required** — the Arc/GoThrough feed rule and the function divergences are pinned by no ADR or reference test. One Codex round on this brief before slice 1's tests (ADR-041).

## Decisions taken at planning (2026-10-17)

Planned with `swift-architect`; the math premises were probed in Swift and `jshell` (desktop JDK 17, not Android ART — hence tolerance except at ADR-019 thresholds).

- **D1 Formula representation — per-arity cases** in `ProgramModel/Formula.swift`: `unaryFunction(UnaryFunction, Formula)`, `binaryFunction(BinaryFunction, Formula, Formula)`, `constant(FormulaConstant)`, `sensor(Sensor)`. Arity is type-enforced (no runtime arity admission, no new `ProgramDocumentError`); synthesized Codable follows `binary`'s existing shape; case names mirror Catroid's `Functions`/`Sensors` so the code.xml importer maps 1:1.
- **D2 Function semantics — mirror Catroid, four pinned divergences.** Trig in degrees (`x · π/180`), inverse trig returns degrees, every result through the existing per-node `normalize` (`exp(1000) → MAX`, `ln(0) → −MAX`), NaN at the root throws (`sqrt(-1)`, `arcsin(2)`). Mirrored: `x mod 0 = x`; `round` is Java 7+ `Math.round` including **NaN → 0** and Long saturation; `min`/`max` return NaN if either argument is NaN (hand-written — both Swift spellings disagree with Java). Divergences:
  - (a) `mod` is the floored modulo: fixes Catroid's `6 mod −3 = −3` (here 0) and its non-terminating loop for `mod(-1e300, 1)`.
  - (b) `arctan2(0, 0) = 0` where Catroid returns a random angle; this also hides IEEE's `atan2(0, −0) = 180`.
  - (c) ±1 ulp libm differences, as in ADR-014.
  - (d) `round` follows Java 7+, not the engine's `javaRound`.
- **D3 `rand` deferred** (see out of scope).
- **D4 Sensors without breaking ADR-042.** `Scope` gains `func value(of sensor: Sensor) -> Double` (explicit, no default). `VariableScope` returns 0; `VariableStoreScope` carries a `VirtualNeedle` snapshot from `scope(forObjectAt:)`. `motionDirection` is folded to (−180, 180] at the read (`VirtualNeedle` keeps its (−360, 360) representation, `VirtualNeedle.swift:95`). The scope is built before `needle.apply` (`Interpreter+Step.swift:141-142`): sensors read the needle *before* the brick moves it.
- **D5 Arc and GoThrough execution.** One `.brick` instruction, **one tick** (ADR-018; Catroid's duration is 0). Geometry lives in `VirtualNeedle` (`arc(radius:sweepDegrees:)`, `goThrough(through:destination:)` → `[NeedleUpdate]`). Direction becomes a signed sweep (LEFT positive); radius is `abs`. Samples **i = 1…100** (Arc's i = 0 is a 1-ulp float/double artefact in Catroid that can turn a 0° arc's heading arbitrarily). **Feed rule**: a sample is fed to the pattern and emitted as `.needleMoved` only if its position differs from the needle's current one (Catroid's `Look.positionChanged` gate, `Look.java:310-332`); if none is fed, one unchanged update is emitted (US-204's rule for turns). **Compute, then commit**: any non-finite sample makes the brick a no-op; a bad formula is catch-and-skip like `moveNSteps`, not Catroid's teleport-to-origin accident (`ArcAction.kt:50-77`). `VirtualNeedle.apply(_:scope:)` returns `[NeedleUpdate]?` (`nil` = not motion; legacy motion returns exactly one).
- **D6 Heading = chord direction, mirrored** (decided 2026-10-17). Each fed sample sets the heading to the chord just travelled, so a quarter arc ends at −89.55°, not −90°. Zigzag reads it per update. Pinned by name so nobody "fixes" it.
- **D7 Angles.** Headings are compass angles (ADR-007: 0° = up, x via sin); Arc's angle around its centre is a math angle (`atan2(y−cy, x−cx)`), exactly as in Catroid. The ADR says so explicitly.
- **D8 File format — keep v1, amend ADR-037** (decided 2026-10-17). v1 may grow additively until the first build is distributed to anyone else; from then on new vocabulary bumps the version, and a document stamps the *lowest* version that can represent it (exhaustive `requiredFormatVersion` walk). Sample JSONs stay byte-identical.
- **D9 Locked formulas.** `ReadOnlyFormulaReason.function` and `.sensor`, each with a localized reason, rendered through `FormulaText`.
- **D10 Model additions.** `ArcDirection { left, right }`; `BrickDefaults` `arcDirection = .left`, `arcRadius = 10`, `arcDegrees = 360`, `goThrough* = 0` — Catroid has no `BrickValues` entry, the provenance is `CategoryBricksFactory.kt:1091-1092`. Slots `.radius`, `.direction`, `.throughX`, `.throughY` (GoThrough's destination reuses `.x`/`.y`); `ParameterValue.arcDirection`, `ParameterEditorKind.arcDirection`.

**New ADRs**: **ADR-046** (formula functions and sensors: D1–D4), **ADR-047** (Arc and GoThrough execution: D5–D7, cross-referencing ADR-018). **Amendments**: ADR-037 (D8), ADR-040 (lock reasons, direction control).

## Acceptance criteria

- [ ] Every `Brick` and `Formula` case round-trips through `ProgramDocument` and is reflexively `==` — a property over a case census that fails to compile when a case is added.
- [ ] Every function matches a characterization table derived from Catroid within 1e-9 (ADR-014); exact where the value is exact or on an ADR-019 threshold (`log(1000) == 3`, `round(-2.5) == -2`, `round(0.49999999999999994) == 0`). Every divergence (D2 a–d) has a named test.
- [ ] No formula built from these functions traps or hangs for any finite inputs — a property over generated trees, including `mod(-MAX, 1)`.
- [ ] Every executed Arc or GoThrough costs exactly one tick, feeds the pattern once per sample whose position changed (at most 100), emits one `.needleMoved` per feed followed by that feed's stitches, and emits exactly one unchanged update when no sample changed position.
- [ ] `arc(left, r, −d)` is event-for-event identical to `arc(right, r, d)`; `arc(_, −r, d)` to `arc(_, r, d)`.
- [ ] Every Arc sample lies on its circle; every GoThrough ends exactly on its destination and passes through its through-point at sample 50 (1e-9).
- [ ] No Arc or GoThrough leaves the needle non-finite; a bad formula or a non-finite sample leaves needle and heading unchanged and emits one update.
- [ ] Sensors read the acting object's own needle at the moment the brick evaluates; `motionDirection` lies in (−180, 180].
- [ ] Every palette kind, row sentence and new formula node has String Catalog entries; Arc's direction is editable as one undoable `replaceBrick`; function and sensor formulas are shown locked with a reason.
- [ ] The new sample runs and exports, and its `.dst` opens correctly in Ink/Stitch (manual check).

## Slices and test-first outline

Every slice touching the format, engine or interpreter is **risky** → `swift-code-reviewer` + one Codex round when green.

0. **Exhaustive dispatch** (risky: yes) — remove `default:` from `Instruction.swift:64`, `VirtualNeedle+Brick.swift:47`, `Interpreter+Step.swift:163` and the embroidery default (~`:212`, restructured into one exhaustive `perform`), and `Script+PairedControl.swift:9-14`. Test side: a `FormulaCensus` (exhaustive switch, one example per case) feeding reflexivity and round-trip properties — closes the `default: false` hole in `Formula.==` (`Formula.swift:34`). A refactor, so the red evidence is a probe: a temporary `Brick` case and the compile errors at every site, recorded. Mutation: restore any one `default:` → the probe compiles there.
1. **Formula representation** (risky: yes — format; ADR-037, ADR-017) — red: `FormulaCodableShapeTests` (exact sorted-keys JSON per new case: the format contract), census round-trip and reflexivity incl. a NaN inside a function argument, `sqrt(sqrt(…))` refused at depth 129, sample bytes unchanged, `ParameterEditorKind` → locked with the right reason; the app's `FormulaText` call rendering in the same commit. Mutations: drop the `.unaryFunction` arm of `==`; function nodes as leaves in `exceedsDepth`; `.sensor` mapped to `.variableReference`.
2. **Function semantics** (risky: yes; ADR-017, ADR-014, ADR-019, ADR-046) — red: `FormulaFunctionTests`, a table per function plus every D2 edge: `max(sqrt(-1), 1)` and `max(1, sqrt(-1))` both throw; `round(sqrt(-1)) == 0`; `mod` over all four sign combinations, `6 mod −3 == 0`, `5 mod 0 == 5`, `mod(-MAX, 1)` terminates; `arctan2(0,0) == 0`, `arctan2(1,0) == 90`; `exp(1000) == MAX`; `tan(90)` finite; `floor(log(1000)) == 3` marked ADR-019. Mutations: Swift `max`; `.rounded()` for round; `truncatingRemainder` for mod; radians in sin; arcsin returning radians; swapped `atan2` arguments; `normalize` skipped.
3. **Sensors** (risky: yes; ADR-042, ADR-018) — red: `StepperSensorTests`: `setVariable(v, objectX)` after a move; `placeAt(x: objectY, y: objectX)` swaps (read before mutate); two objects read their own needles; two scripts on one object see each other's moves; direction after `turnRight(270)` is −90, after `turnLeft(180)` is 180, after `pointInDirection(540)` is 180; `VariableScope` returns 0. Mutations: unfolded heading; fold to [−180, 180); always object 0's needle; scope built after `apply`.
4. **Arc** (risky: yes — engine, interpreter, format; ADR-018/014/020/007, ADR-047) — red: `ArcTests` at needle and stepper level: quarter LEFT/RIGHT ends at (∓10, 10) with heading ∓89.55 (`finalHeadingIsTheLastChordNotTheTangent`); the negative-degree and negative-radius equivalences as whole event lists; every sample on the circle; 100 feeds; radius 0 and degrees 0 each one unchanged update with the heading unchanged; bad formula skips; `r = MAX` skips with a finite needle; `[arc, move]` takes 2 ticks; zigzag along an arc equals feeding the expected `NeedleUpdate` list straight into `ZigzagStitchPattern` (oracle by composition); a full-circle DST round-trips through `DSTFileReader` with every delta ≤ 121. EditorCore arms (`BrickKind`, `template`, `parameters`/`replacing`, `ProgramDocument.formulas`, palette) and the minimal app arms land here, forced by the exhaustive switches. One check of `RunBudget`/driver allocation for `repeat 1000 { arc }` (100k events) against ADR-043's bar. Mutations: i = 0 included or 101 samples; tangent heading; normal sign swapped; negative-degree flip dropped; only the last sample fed; heading updated on a zero chord; commit before the finiteness check.
5. **GoThrough** (risky: yes) — red: sample 50 equals T within 1e-9; endpoint equals E exactly; defaults from the origin give one unchanged update; from (100, 0) the curve overshoots to x = −12.5 at t = 0.75 (Catroid characterization); bad formula skips; non-finite control point skips; per-chord heading. Mutations: control point = T; heading from the first chord; all 101 samples fed.
6. **App wiring** (risky: no; ADR-039/040/045) — Arc and GoThrough in `BrickLeadingView` and `PalettePresentation`; row sentences as whole catalog entries (Arc left and right as two sentences, plural twin for degrees; Catroid's `arc_with_radius`, `arc_for_degrees`, `go_through`, `go_through_target` as source wording); a segmented left/right picker (one `replaceBrick`, nothing to coalesce); four number fields for GoThrough. Tests: palette order, template defaults against Catroid `:1091-1092`, sentences, `AppStringsTests` completeness, the direction edit as one undo entry, lock reasons. Mutations: swapped left/right keys; the picker writing the opposite direction; a palette entry missing. Simulator screenshots.
7. **Sample** (risky: yes — checked-in program JSON; ADR-037, ADR-019) — a new `SampleID` using Arc, GoThrough and functions, guarded by a JSON round-trip resource like US-301's, plus an ADR-019 threshold screen. Exported and checked in Ink/Stitch.

**PR split** (~1,100–1,300 lines of non-test Swift, so split; an engine-only PR is impossible because new cases break the app's exhaustive switches): **PR 1 — formula language**, slices 0–3 with their app arms (~650). **PR 2 — path bricks**, slices 4–7 (~650).

## Verification at handover

- Every slice mutation-checked and recorded; risky slices reviewed when green (reviewer + one Codex round each), then the PR's Codex loop (cap 5).
- Simulator screenshots of the palette, an Arc row with its direction control, a GoThrough row, a locked function formula and the sample's preview.
- **Ink/Stitch**: the sample's `.dst` and a full-circle Arc in running and zigzag stitch.
- **External golden, if available**: an arc and curve `.dst` exported from the Android Embroidery Designer — the only external check of the D5 feed rule (compare at ±1 unit, float vs Double).
- Pre-beta accessibility questions: VoiceOver reading of a locked function formula; the segmented direction control's label and value.
- Follow-ups to file: the `javaRound` backlog entry and the ADR-012 wording note (ADR-032 invariant 3: every copy of "floor(x + 0.5) = Math.round").

## References

- ADR-007, 012, 014, 017, 018, 019, 020, 033, 034, 037, 040, 041, 042, 043, 045.
- Catroid (`catroid/src/main/java/org/catrobat/catroid/`): `content/actions/ArcAction.kt`, `content/actions/GoThroughAction.kt`, `content/bricks/ArcBrick.kt`, `content/bricks/GoThroughBrick.kt`, `content/ActionFactory.java:625-652`, `ui/fragment/CategoryBricksFactory.kt:1039-1094`, `formulaeditor/function/MathFunctionProvider.java`, `formulaeditor/FormulaElement.java`, `formulaeditor/common/FormulaElementOperations.kt:149-190`, `content/Look.java:300-332, 452-461, 676-698`, `embroidery/SimpleRunningStitch.java:51-79`.
- Predecessors: US-204 (needle updates for turns), US-301 (sample guards), US-410 (read-only formulas).
