# Language-test runner

**Status**: Planned — 2026-11-03 | **Epic**: E3 (program model & interpreter) | **Branch**: `feature/language-test-runner` (PR 1; PR 2 gets its own branch)

**Goal**: the engine runs the Catrobat Language Tests, the implementation-independent `.catrobat` programs Catroid ships in `catroid/src/androidTest/assets/catrobatTests/`, headlessly inside `swift test`, and reports how many of the 215 pass. Every test is pinned to an expected class: pass, expected failure (with its ADR) or unsupported (with the features it needs). A test that changes class turns the suite red until the table is updated on purpose. A partial `code.xml` → `Program` importer, the S* `.catrobat` import's first half, comes with it.

**In scope**
- A `code.xml` importer for the supported bricks, formulas and the two Start-script shapes, in a new `CatrobatImport` target.
- `AssertEquals`, `FinishStage`, `ExitStage` and `WaitTillIdle` as **harness steps**: interpreted, but never `Brick` cases. So none of them reaches `BrickKind`, the palette or `ProgramDocument`.
- An empty script (`EmptyScript`) is skipped on import.
- All 215 `code.xml` files committed as fixtures, with a provenance manifest and a reproducible extraction script.
- A parameterised runner with pinned per-test classes and pinned summary counts.

**Out of scope** (each deliberate)
- **Strings as values** (decided 2026-11-03). The Variables brief deferred them to this feature (its D1); they are deferred again. Our values stay `Double` (ADR-048), and a string that would be *compared or stored* is refused on import (D4). That costs two runnable tests: `bricks/control/testForLoopWithChangeVariableBrick` and `data/testSetAddVar`.
- Everything ADR-001 leaves out: lists, broadcasts, clones, looks, physics, touch and colour sensors, user-defined bricks. That is about 177 of the 215.
- `rand` (deferred by ADR-046; it would add `formula/testRandomFunction`).
- Importing a `.catrobat` in the app, and unzipping. The fixtures are extracted `code.xml` files, so the engine needs no zip.
- Moving the suite into Catrobat's planned language-specification repository, writing new language tests, and triaging Catroid's open `catrobatTests` PRs (ROADMAP, 2026-10-19 update).
- `WaitTillIdle` in the palette. It is a real Catroid control brick, but a harness step here; making it user-facing needs a `Brick` case and a format addition, and with one object in the app it is a no-op anyway.

## Decisions taken at planning (2026-11-03)

Planned with `swift-architect` against a fresh Catroid clone (`develop` at `9035dc7cb`, 2026-10-26; `CURRENT_CATROBAT_LANGUAGE_VERSION = 1.14`, `common/Constants.java:45`; the test assets last changed in `e993a6a52`, 2026-04-07). Four decisions were taken by Sebastian on 2026-11-03: the version window (D1), refusing strings (D4), all three small additions (D8, D9) and committing all 215 fixtures (D13). Catroid paths below are relative to `catroid/src/main/java/org/catrobat/catroid/` unless they start with `catroid/`.

- **Feasibility (re-measured).** Static analysis of all 215 `code.xml` files, covering the bricks, scripts, functions and sensors each one uses:

  | Class | Count |
  |---|---|
  | Runnable with importer + AssertEquals + FinishStage | 34 |
  | …refused for string values (D4) | 2 |
  | …predicted expected failures | 2: `formula/testFloatingPointArithmetic` (decimal128, ADR-048), `formula/testArctangent2FunctionZeroParameters` (Catroid's random angle for `arctan2(0,0)`, `formulaeditor/function/MathFunctionProvider.java:79-80`; ours is 0, ADR-046) |
  | **Predicted pass** | **30** |
  | + ExitStage, EmptyScript, WaitTillIdle | +4: `bricks/control/testRepeatUntilBrick`, `bricks/motion/testChangeXby`, `testEmptyEvent`, `testWaitUntilAllOtherScriptsHaveStopped` |
  | Out of scope (ADR-001, `rand`) | ~177 |

  The runner measures the real figure. Until slice 6 lands, the prediction is not a claim.

- **D1 Version window: 0.99995 ≤ version ≤ 1.14** (decided 2026-11-03; it supersedes the 2026-10-19 decision to bring old tests up to 1.14 by re-saving them through Catroid). **None of the 215 tests is at 1.14** and only one is at 1.13. The 34 runnable ones span 12 versions from 0.99995 to 1.12. For our bricks the format is the same across that window:
  - The 1.13 and 1.14 bumps changed no format code. 1.14 (`a949f79b5`) added XStream aliases for plot and laser bricks; 1.13 (`18645e92e`) touched only `Constants.java`.
  - Catroid's load-time upgrades (`ProjectManager.java:143-175`) don't reach our set, except `updateDirectionProperty` for versions ≤ 1.03 (`OBJECT_ROTATION` → `MOTION_DIRECTION`, `formulaeditor/Formula.java:114-119`). The importer **refuses `OBJECT_ROTATION`** as an unsupported sensor; no runnable test uses it.
  - The parent/child tag pairs of every runnable test match the 1.11–1.13 tests'. The two outliers, both read by Catroid 1.14's XStream, are accepted: a variable written as text (`<userVariable>Counter</userVariable>`) and a fully qualified tag (`<org.catrobat.catroid.content.bricks.AssertEqualsBrick …>`).

  Re-saving would have needed an Android round trip and churned brick IDs and `reference=` paths for no format gain. A version outside the window is refused (`version`). One target still holds: the importer parses the 1.14 shape, and nothing reaches back past it. The supervisor is informed, not asked.

- **D2 AssertEquals equality.** Catroid evaluates both sides with `interpretObject` (`content/actions/AssertEqualsAction.kt:49-50`) and passes iff `actual == expected || actual.toDouble() == expected.toDouble()` on their strings (`content/actions/AssertAction.kt:45-50`). NUMBER and STRING nodes return their raw text (`formulaeditor/FormulaElement.java:408-410`), so a literal `1` and a computed `1.0` compare numerically. Over our `Double` values that reduces to ADR-048's one equality, the existing `Double.isSameValue(as:)` (`ProgramModel/DoubleEquality.swift:5`, made `package`): NaN = NaN (Catroid's `"NaN" == "NaN"`) and −0 = +0 (`toDouble ==`). Evaluation must not throw: a new `package func interpretValue(scope:)` returns the raw `Double`, NaN included, where `interpretDouble` throws on NaN (`Formula+Evaluation.swift:9-15`).

- **D3 Harness steps stay out of `Brick`.** The importer produces an `ImportedProgram` that mirrors `Program`, with scripts as `[ImportedStep]` = `.brick(Brick) | .assertEquals(actual:expected:position:) | .finishStage | .exitStage | .waitTillIdle`. `ImportedProgram.program()` refuses harness steps, which serves the later app import. The interpreter gains a `package init(harness:)` over `[ScriptStep]` and an `Instruction.harness` case. `compile` and `validate()` work on the brick projection; harness steps are leaves. The outcome is a `package var harnessResult`, not new `InterpreterEvent` cases, so the exhaustive switches in StagePreview and the app stay untouched. ADR-037 holds by construction.

- **D4 String literals are mapped by context, mirroring Catroid, or refused** (refusal decided 2026-11-03). A literal matching Java's decimal grammar without an `fFdD` suffix, or exactly `NaN`, becomes `.number(Double(s))`. Otherwise:

  | Where the literal sits | Catroid | Import as |
  |---|---|---|
  | Brick root (a number slot) | `Double.valueOf`; on failure `InterpretationException`, which acts as NaN (`formulaeditor/Formula.java:139-161`) | `.number(.nan)` |
  | Operator operand | NaN on failure (`formulaeditor/common/FormulaElementOperations.kt:79-88`) | `.number(.nan)` |
  | Function argument | `tryParseDouble` rejects `fFdD` (so `"Infinity"` too), and a null argument makes the function return 0.0 (`formulaeditor/common/Conversions.kt:35-44`; `UnaryFunction.kt`, `BinaryFunction.kt`: `?: return 0.0`) | the whole call folds to `.number(0)` (`ARCSIN('abc')` expects `FALSE()`) |
  | AssertEquals operand, SetVariable/ChangeVariable value | compared or stored as a real string | **refused** (`stringValue(context)`); mapping to NaN would let `"abc" = "xyz"` pass |

  A non-finite NUMBER literal is refused, since Catroid keeps the raw string `"1e400"` rather than normalising it (`FormulaElementOperations.kt:91-104`).

- **D5 Run outcome.** **The first result wins, and a failure stops the run.** `finishTestWithResult` ignores later results while the stage is finishing (`stage/StageActivity.java:490-498`), and a failing assert's `act` returns false. A failure reports the object, script and step index with expected and actual. `FinishStage` reports success (`content/actions/FinishStageAction.kt`). `ExitStage` is `createFinishStageAction(true)` (`content/bricks/ExitStageBrick.java:43`), so it ends the run without a result. A run that ends without a result, through ExitStage or by every thread finishing, fails as `endedWithoutResult`; Catroid waits out its timeout and fails. In both tests that use it, ExitStage comes after FinishStage.

- **D6 Tick cost and budget.** Each of AssertEquals, FinishStage and ExitStage is one action, because libgdx `SequenceAction` advances one child per frame. Like any action, it is deferred when the thread already acted this tick. The budget is **600 ticks**, Catroid's `TIMEOUT = 10_000` ms (`catroid/src/androidTest/java/org/catrobat/catroid/catrobattestrunner/CatrobatTestRunner.kt:68`) at `tickDelta` 1/60. Running out of budget fails as `budgetExhausted`. No retries; Catroid uses 5 (`:50`). Every run records the ticks it used, so a test that passes only under a looser budget shows up as a finding.

- **D7 Import mapping.**
  - **References:** XStream relative paths, where `name[n]` is 1-based and counts only siblings with the same tag (`../../brick[2]/userVariable`, `../../scenes/scene/objectList/object[2]/…`). In the runnable set, references only ever point at `userVariable`. An unresolved reference is refused.
  - **Declarations:** `programVariableList` maps to `Program.variables` and an object's `userVariables` to `Object.variables`. Both are lists of references to the variable's first use. Formulas read variables by name (the `USER_VARIABLE` value), which matches our lookup. Catroid binds identity; we bind names. They differ only when an object and the project declare the same name, so the importer **refuses that collision** (`variableShadowing`) rather than guess.
  - **Structure:** `loopBricks` becomes body + `.loopEnd`. `IfLogicBeginBrick` becomes `ifElse` + `ifBranchBricks` + `.elseBranch` + `elseBranchBricks` + `.ifEnd`. `IfThenLogicBeginBrick` becomes `ifThen` + `ifBranchBricks` + `.ifEnd` (ADR-008). A `commentedOut` brick is skipped with its whole subtree (`content/Script.java:132`, `content/bricks/RepeatBrick.java:184`), and so is a commented-out script (`Script.java:101`). `NoteBrick` is dropped. A BRACKET node passes its child through; unary `MINUS` becomes `unaryMinus` and `LOGICAL_NOT` becomes `logicalNot`. A non-empty `additionalChildren` is refused. ADR-037's 128-node depth cap applies.
  - **Pose:** start at (0, 0) with heading **90** (`content/Look.java:88`); `testMoveXStepsFunction` depends on it.
  - **Scenes:** first scene only; more than one is refused. Catroid plays one scene, while `Interpreter.swift:42` runs every object it is given.
  - **Errors:** `throws(CatrobatImportError)`, which **collects every** blocker rather than stopping at the first: `brick(name)`, `script(name)`, `function(name)`, `sensor(name)`, `elementType`, `stringValue(context)`, `version`, `multipleScenes`, `variableShadowing`, `unresolvedReference`, `malformed`. The runner builds its blocker histogram from these.

- **D8 WaitTillIdle** (decided 2026-11-03). Catroid's action is true iff every actor on the stage has no running script, or only the script running this action (`content/actions/WaitTillIdleAction.java:35-58`). Mirrored over our threads: one poll per tick, an action like `waitUntil` (ADR-049), satisfied in the tick every *other* thread has finished. Mirrored too: two threads each in a WaitTillIdle never release each other, because neither counts the other as idle. A stage with no objects is never idle. A tick-order question stays open for the Codex round: does a thread finishing earlier in the same tick count?

- **D9 EmptyScript** (decided 2026-11-03). Skipped on import; it has no bricks and no trigger.

- **D10 Package layout (ADR-042 amendment).** A new target, **`CatrobatImport`**, depends on `ProgramModel` only and is vended by no product, so no `pbxproj` change: eight targets, five products. XML is read with a Foundation `XMLParser` SAX pass into a small `Sendable` element tree (`XMLDocument` is macOS-only), with `#if canImport(FoundationXML)` so the target can build on Linux. Nothing builds on Linux yet (US-317), so this only keeps that door open. The test target `LanguageTestsTests` holds the fixtures and the runner, and depends on `CatrobatImport` and `Interpreter`; a small adapter there maps `ImportedStep` to `ScriptStep`.

- **D11 Fixtures** (decided 2026-11-03: all 215). Stored at `Tests/LanguageTestsTests/Resources/catrobatTests/<original path>/code.xml`, declared `.copy` so the tree survives. About 3 MB. `manifest.json` records, per test, the original zip path, the sha256 of the zip and of `code.xml`, and the language version, plus the Catroid commit and the asset directory's last commit. A `PROVENANCE.md` (AGPL-3.0, verbatim data) sits beside it. `scripts/extract-language-tests.sh <catroid-checkout>` regenerates the fixtures and manifest deterministically.

- **D12 The ratchet.** `@Test(arguments: LanguageTestCatalog.all)`, where each case carries a pinned class: `pass`, `expectedFailure(reason, adr)` or `unsupported(Set<Blocker>)`. An expected failure runs inside `withKnownIssue`, which fails when no issue is recorded, so the list cannot rot. That premise is executed first (ADR-032 invariant 4). An unsupported case asserts that its blockers are exactly the pinned set. A summary test pins the per-class counts and attaches `N/215` and the blocker histogram.

**New ADR**: **ADR-051**, Catrobat language tests: the version window, the import mapping and string contexts, harness steps, equality, outcome, ticks and budget, WaitTillIdle (D1–D9, D12). **Amendments**: ADR-042 (D10). **ROADMAP**: the 2026-10-19 re-save decision is superseded by D1, recorded as a dated update, not by editing it.

## Acceptance criteria

- [ ] All 215 fixtures are present, and their hashes match the manifest; the extraction script reproduces both from the pinned Catroid commit.
- [ ] Every one of the 215 imports or fails with typed blockers, and none crashes. Every successful import passes `validate()`.
- [ ] Every Catroid function, operator, sensor and element-type name that `Formula` supports maps to its case. A census over `UnaryFunction`/`BinaryFunction`/`FormulaConstant`/`Sensor.allCases` fails to compile, or fails, when one is missed.
- [ ] Each D4 string context is pinned by a named test, including a refused assert string and the function-call fold to 0.
- [ ] AssertEquals passes and fails exactly by `isSameValue` (NaN = NaN, −0 = +0, `1` vs `1.0`). A failure stops the run, the first result wins across threads, and assert, finish and exit each cost one tick, observed from a second script.
- [ ] A run that ends without a result, or exhausts 600 ticks, fails with its own reason, and every run reports its tick count.
- [ ] WaitTillIdle is released exactly when every other thread has finished; two waiters never release each other.
- [ ] Every one of the 215 cases matches its pinned class, the summary counts are pinned, and an expected failure that starts passing turns the suite red.
- [ ] No existing engine or app test changes, and `BrickKind`, `ProgramDocument` and the sample JSONs are byte-identical (`git diff --stat` on them is empty).

## Slices and test-first outline

Slices 2–5 are **risky** (program format, interpreter): `swift-code-reviewer` plus one Codex round each when green. Estimated at ~1,150 lines of non-test code. Four risky slices are a lot for one review, so this ships as **two PRs**: **PR 1 = slices 1–4** (fixtures and importer, ending with the import property) and **PR 2 = slices 5–7** (harness, WaitTillIdle, runner).

1. **Fixtures, manifest, catalog** (risky: no) — red: the catalog has 215 entries; every manifest entry has a fixture and vice versa; the hashes match; the versions are within D1's window or the case is pinned `unsupported(.version)`. Mutations: delete a fixture; flip a byte; drop a manifest entry.
2. **XML tree and reference resolver** (risky: yes; D7) — red: elements, text and attributes; same-tag 1-based indexing; `..` chains; a fully qualified sibling not counted towards `brick[n]`; an unresolved reference → typed error; malformed XML → `malformed`, never a trap. Mutations: 0-based index; counting all siblings; ignoring `..`.
3. **Formula import** (risky: yes; D2, D4, ADR-046/048) — red: each element type and operator, with precedence taken from the tree; the census; the four string contexts; `fFdD` and `"Infinity"`; a non-finite literal; the depth cap. Mutations: swap PLUS and MINUS; drop the fold (`sin('abc')` → NaN); accept `fFdD`; NaN-map an assert string.
4. **Program and brick import** (risky: yes; D1, D7, D9, ADR-008) — red: every supported brick and its parameters; loop and If flattening; else placement; a commented-out subtree and script; Note; EmptyScript; declaration scope; the text-form variable; the shadowing refusal; heading 90; one scene; `OBJECT_ROTATION`; the collect-all error; the property "every successful import of the 215 passes `validate()`". Mutations: else body in the then branch; keep commented-out bricks; heading 0; a project variable in object scope; stop at the first blocker.
5. **Harness in the interpreter** (risky: yes; D2, D3, D5, D6) — red: NaN = NaN; −0 = +0; `1` vs `1.0`; a failure stops the run (a later stitch is never emitted); the first result wins within one tick across threads; an assert costs one tick, observed from a second script; a finish inside a loop; ExitStage; ended without a result; budget exhausted; the tick count reported; the whole existing suite unchanged. Mutations: `==` instead of `isSameValue`; a zero-tick assert; a failure that doesn't stop the run; last result wins; an off-by-one budget.
6. **WaitTillIdle** (risky: yes; D8) — red: released in the tick the last other thread finishes; not released while any other thread runs, on its own object or another; two waiters never release each other; one poll per tick. Mutations: count only this object's threads; count waiters as idle; release one tick late.
7. **Runner and ratchet** (risky: no; D12) — red: the 215 cases each match their class; known-issue strictness, executed first with a deliberately passing case; the pinned summary counts. Mutations: remove an expected-failure entry; list a passing test as an expected failure; break the equality rule (the summary count moves).

## Verification at handover

- Every slice mutation-checked and recorded; risky slices reviewed when green (reviewer + one Codex round each), then each PR's Codex loop (cap 5).
- No UI, no DST output: no screenshots and no Ink/Stitch check. State this in the PR.
- Re-run the static feasibility count against the runner's measured `N/215`; any difference is journalled.
- US-326 (setVariable NaN → 0 here, NaN in Catroid): record whether any runnable test's outcome depends on it.
- Report `N/215` and the blocker histogram to the supervisor (inform, not ask), with D1's version window.

## Codex brief review — what to attack

- D1: is "no format difference in the window" true for every element our importer reads, not just tag pairs (attribute names, `formulaList` category keys, `isUserDefined`, brick `commentedOut` vs older `isCommentedOut`)?
- D2/D5: does `interpretObject` on a boolean root (`TRUE()`, a comparison) produce `"true"` in Catroid, so that `1.0 == "true"` fails where our 1 = 1 passes? Is "first result wins" exact when two threads report in the same frame?
- D4: are the four contexts exhaustive (a brick root that takes a string, like `setThreadColor`; a comparison operand; a variable read of a stored string)?
- D6: is a failing assert's tick the one that ends the run, or does the frame finish first? Does the 600-tick budget match a 10 s wall clock at 60 fps closely enough, given Catroid's frame pacing?
- D7: is refusing name shadowing too strict for the runnable set? Is heading 90 the only start-pose difference (ADR-007's 0° = up)?
- D8: the tick order of WaitTillIdle relative to a thread that finishes earlier in the same tick; an object with no scripts (Catroid's background) counting as idle.
- D12: does `withKnownIssue` really fail when no issue is recorded, under parameterised tests?

## References

- ADR-001, 007, 008, 017, 018, 032, 037, 041, 042, 046, 048, 049; backlog US-317, US-326; the Variables brief (D1, D6).
- Catroid (`catroid/src/main/java/org/catrobat/catroid/`): `content/actions/AssertAction.kt:45-50`, `AssertEqualsAction.kt:49-50`, `FinishStageAction.kt`, `WaitTillIdleAction.java`, `content/bricks/ExitStageBrick.java:43`, `stage/StageActivity.java:490-498`, `formulaeditor/FormulaElement.java:408-410`, `formulaeditor/Formula.java:114-161`, `formulaeditor/common/FormulaElementOperations.kt:79-104`, `formulaeditor/common/Conversions.kt:35-44`, `formulaeditor/function/MathFunctionProvider.java:79-80`, `content/Look.java:88`, `content/Script.java:101, 132`, `io/XstreamSerializer.java`, `ProjectManager.java:143-175`, `common/Constants.java:45`; the runner `catroid/src/androidTest/java/org/catrobat/catroid/catrobattestrunner/CatrobatTestRunner.kt:50, 68`; the tests in `catroid/src/androidTest/assets/catrobatTests/`.
- Planning analysis scripts (not committed): the swift-architect run of 2026-11-03.
