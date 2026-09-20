# US-401 — `EditorCore`: brick kinds, templates, addressing, indentation

**Epic**: E5 Block editor | **Estimate**: ~4 h | **Depends on**: — (M2 `ProgramModel`, shipped)

**Status**: Implemented — 2026-09-20, **not yet closed out**. All eight acceptance criteria are met and all seven test-plan items landed, plus a thirteenth test for the addressing criterion the plan's seven items do not reach. **334 engine tests green** (from 257), CI green on `dd34f5f`, SwiftLint clean by exit code. PR [#51](https://github.com/stoneacher/catty-embroidery/pull/51).

**What is outstanding is the cross-vendor review loop, and it is blocked externally.** Rounds 1 and 2 ran: **9 findings, all valid, none rejected**, severity **Medium → Medium**. That is *flat*, which the project's stop condition explicitly does not accept as convergence, and both rounds changed code — so **round 3 is required**. It did not run: Codex returned `You've hit your usage limit … try again at 7:44 PM`. The story is therefore **not Done**, and this line says so rather than rounding up.

Not one finding was in the shipped vocabulary. Codex independently confirmed all 23 kind mappings, both exhaustive switches, the pair-shaped opener templates, every one of the eight new `BrickDefaults` values against `BrickValues.java`, and ran 29 524 generated opener/end sequences against its own stack oracle with no disagreement on `indentDepths`. All nine findings were in the guards, the fixtures or the comments.

**Story**: As the developer, I want the editor's vocabulary to exist as pure values in its own target, so every later editor story is a transformation of tested types rather than a view inventing its own model.

This is the M4 counterpart of US-302: the load-bearing values land first, on the fast `swift test` gate, before any pixel exists. Nothing here is user-visible.

## What this story creates

- The **`EditorCore` target**, depending on `ProgramModel` only (ADR-033), vended through the **existing `ProgramModel` product** so the app can `import EditorCore` with no `pbxproj` change.
- **`BrickKind`** — a payload-free mirror of `Brick`, `CaseIterable` and `Sendable`. It is the spine of the milestone: palette rows, the same-kind guard on `replaceBrick` (US-402), and row labels (US-407) all key off it.
- **`BrickKind.template() -> [Brick]`** — a new brick of that kind seeded from `BrickDefaults`, returning an **array** because a loop opener yields two bricks (ADR-035).
- **`ScriptAddress` / `BrickAddress`** — index-based addressing (ADR-034), `Hashable` and `Sendable`.
- **`Script.indentDepths`** — the per-row nesting depth the list view renders as indentation, as a pure function.

## Acceptance criteria

- [x] `EditorCore` exists as a target depending on `ProgramModel` **only** among package targets, and imports **no SwiftUI and no CoreGraphics**. **Foundation is permitted** — ADR-033 restricts *package dependencies*, not the standard library, and US-404 puts `Data`/`JSONEncoder` in this target, so a Foundation ban would make that story unbuildable. This mirrors what ADR-022 means by `StagePreview` being "Foundation-only": Foundation and nothing above it.
- [x] An isolation test pins the above. **It cannot be modelled on `StagePreviewTargetIsolationTests`' mechanism**, which does not scan source imports — it binds public APIs to explicit function types, and its own comment distinguishes that from dependency enforcement. The dependency restriction is enforced by the manifest and by the build; what the test adds is a guard against a SwiftUI/CoreGraphics import creeping in, which needs a source scan or an equivalent. Choose the mechanism deliberately and say which guarantee it actually gives.
- [x] **`import EditorCore` compiles in the app target with `project.pbxproj` unmodified.** Verified at planning time and re-verified here as the story's own first step; if it fails, stop and raise a human Xcode session rather than working around it.
- [x] `BrickKind`'s `Brick → BrickKind` switch is **exhaustive with no `default:`** — the pattern `RunBatch.reducing` already uses — so adding a `Brick` case is a compile error rather than a silent gap.
- [x] `BrickKind.template()` seeds every parameter from `BrickDefaults` where a constant exists, and **this story adds the ones that do not**. `BrickDefaults` holds exactly **nine** constants — `moveSteps`, `turnDegrees`, `placeAtX`, `placeAtY`, `stitchLength`, `zigZagLength`, `zigZagWidth`, `threadColorHex`, `waitSeconds` — and the palette needs more than that. The missing set, verified against `BrickValues.java` : a **repeat count**; a **variable name and initial value** for `setVariable`/`changeVariableBy`; an **output file name** for `writeEmbroideryToFile`; **`pointInDirection`**, which Catroid gives as `POINT_IN_DIRECTION = 90` (`BrickValues.java:41`) — note it is **not** `turnDegrees`, which is 15, so reusing the existing angle constant would ship a different default direction; and **`changeXBy`/`changeYBy`**, which Catroid gives as separate `CHANGE_X_BY`/`CHANGE_Y_BY = 10` (`:37-38`) — numerically equal to `moveSteps`, so they need their own named constants rather than accidental reuse. Each new constant is added to `BrickDefaults` **with its Catroid provenance in a comment**, matching the existing nine; where Catroid has no counterpart, say so in the comment rather than inventing a silent default.
- [x] A loop opener's template is **two** bricks, opener then `.loopEnd`.
- [x] `Script.indentDepths` returns one depth per brick: body bricks are deeper than their opener, a `loopEnd` sits at its **opener's** depth (not the body's), and nested loops accumulate. An **unbalanced** script — which the model permits even though no `EditAction` can create one — yields depths without trapping and without going negative.
- [x] `BrickAddress`/`ScriptAddress` address a brick through `Program → Scene → Object → Script → index`. M4's working program is realistically one scene / one object / one script (both shipped samples are), but the address stays honest against the model that permits more.

**Not in this story**: any mutation. `EditAction` and `apply` are US-402's. This story's types are inert.

## Test-first plan

1. `EditorCore` imports no SwiftUI and no CoreGraphics — by whichever mechanism the criterion above settles on. Foundation is allowed and is **not** asserted against.
2. Every `Brick` case maps to a distinct `BrickKind`, asserted by iterating `BrickKind.allCases` and round-tripping a template through the mapping — which also proves `template()` is total.
3. `BrickKind.repeatLoop.template()` is exactly `[.repeatLoop(times:.number(…)),.loopEnd]`, and `.forever.template()` is `[.forever,.loopEnd]`.
4. Every non-loop template is exactly one brick.
5. Each template's parameter values equal the corresponding `BrickDefaults` constant — asserted against `BrickDefaults` by name, not against re-typed literals, so a change to the default cannot leave this test passing against a stale copy. It covers the **new** constants as well as the existing nine. **What it does *not* prove is that the implementation references the constant**: mutating `.number(BrickDefaults.moveSteps)` to `.number(10)` leaves it green, because the values are equal today. The guarantee is "the template tracks the constant if the constant changes", and the story claims only that; a structural check is the alternative if the stronger guarantee is wanted.
6. `indentDepths` on a flat script is all zeros; on one loop it is `[0, 1, …, 1, 0]` with the `loopEnd` back at 0; on nested loops it accumulates; on an unbalanced script it returns a value rather than trapping and never goes below 0.
7. `indentDepths` returns exactly `bricks.count` elements for every script it is given, including the empty one.

**A note on the red phase, from US-308's and US-309's experience**: most reds here will be *compile* failures, which prove nothing about the assertions. Before implementing, check the cheap question that story produced — does each new test file reference a symbol this story adds? — and afterwards prove the discriminating assertions by **mutation** (ADR-032 invariant 2), not by having watched them go green. The `indentDepths` tests are the ones worth mutating: a `loopEnd` placed at body depth instead of opener depth is the plausible mistake and several of the tests above will not see it.

## References

- ADR-033 (the target, the product-vending trick, the pure funnel), ADR-034 (index addressing), ADR-035 (pair semantics, which decides `template()`'s array return)
- ADR-008 and its 2026-07-20 clarification — flat scripts, paired control bricks, nesting is positional
- ADR-016 / ADR-022 — the inward-only DAG this target joins
- `Sources/ProgramModel/Brick.swift` — `BrickDefaults`, already present and already naming M4
- `Sources/ProgramModel/Script+PairedControl.swift` — `opensLoop`, `isLoopEnd`, `matchingEnd(ofBrickAt:)`, `range(ofPairAt:)`, which `indentDepths` should use rather than re-deriving
- `Catroid/.../CategoryBricksFactory.kt:1039-1056` — the Embroidery category, the parity target for which kinds exist

## Close-out notes

### Three declared deviations from the story text

1. **Eight new `BrickDefaults` constants, not seven.** The criterion asks for "a variable name and initial value" — one value. Catroid has **two** distinct constants, `SET_VARIABLE` (`BrickValues.java:138`) and `CHANGE_VARIABLE` (`:140`), both `1d`. They get two names by this story's own `CHANGE_X_BY`/`CHANGE_Y_BY` reasoning: equal values today are not the same decision.
2. **`indentDepths` uses `opensLoop`/`isLoopEnd` but not `matchingEnd(ofBrickAt:)`/`range(ofPairAt:)`**, against the References section's note. `matchingEnd` returns `nil` for an opener that is never closed, so a pair-resolving implementation needs a fallback for exactly the unbalanced case the criteria require it to survive — and that fallback is the depth counter. It is the same single scan `matchingEnd` performs internally, run once for the whole list instead of once per opener.
3. **A thirteenth test**, because the seven-point test plan has no item for the addressing criterion, which would otherwise have shipped untested.

### Decisions this story made that the plan did not anticipate

- **SwiftLint's `cyclomatic_complexity` now ignores case statements.** The 23-arm exhaustive no-`default:` switch ADR-033 *requires* scores 23 against a threshold of 10 while containing no conditional branching. This is the repo's first `.swiftlint.yml` rule relaxation; there are still no `swiftlint:disable` comments anywhere. US-402, US-407 and US-409 all switch over the same 23 kinds.
- **The evaluated-manifest check lives in CI, not in the test suite.** `swift package dump-package` is the only oracle that sees a dependency appended after the initializer, and spawning it from inside `swift test` **deadlocks on SwiftPM's build lock** — measured at 608 s before being killed, not merely slow. The in-suite pin stays as the fast local signal and states what it cannot see. ADR-023's division, arriving on its own.

### Notes for later stories

- **US-407 / US-410 inherit a UI obligation from `BrickDefaults.variableName == ""`.** Catroid has no default variable name — `SetVariableBrick(double)` seeds only the value and picks the name from a spinner over the project's variables — so `""` is the model's honest spelling of "none chosen yet" rather than an invented English string in a package with no localisation. It cannot misbehave (`VariableScope.value(of:)` resolves an unknown name to 0, Catroid `Conversions.FALSE` parity). **A row and a parameter editor must render it as a placeholder, not as blank space.**
- **US-402 owns the resolver and its failure policy.** `BrickAddress` deliberately ships without `Program.brick(at:)`: the out-of-bounds policy is a *rejection* rather than an optional (ADR-033), and writing the resolver here would mean writing it without its semantics. `EditorAddressTests` has a bounds-checked private traversal for its own use only.
- **A red-phase lesson, re-learned from US-302 rather than inherited.** A test that subscripts raw **traps** under a wrong-index mutation and takes its whole parallel bundle down instead of failing one test — hiding every other suite's result. Bounds-check the traversal in any test that addresses into a structure.
- **The import scan is a heuristic, and its limit is stated in the file.** It catches every spelling an ordinary source file can express — including the split, comment-interrupted, backtick-escaped and `;`-separated forms two review rounds found — but it is not a lexer, so a string literal containing `/*` can hide an import. A **Linux engine-test job** would make this structural rather than heuristic, since SwiftUI/UIKit/CoreGraphics do not exist there; engine tests currently run on `macos-26` (checked, not assumed). That is a CI-wide change, not a US-401 line item.

### Documentation debt for the M4 `swift-documenter` pass

`Packages/EmbroideryEngine/README.md` reproduces `BrickDefaults` with exactly the original nine constants and enumerates five targets and the DAG. Both are now stale: seventeen constants, six targets, five products. Left to milestone close deliberately, recorded here so the drift check does not have to rediscover it.

### No new ADR

ADR-033, ADR-034 and ADR-035 pinned everything this story needed at M4 planning. ADR-036…040 stay with their owner stories.

### Manual Ink/Stitch verification

**Not needed.** Nothing in this story reaches the DST writer — the types are inert and no byte is emitted. The first user-authored program to reach the writer is M4's milestone-close item.
