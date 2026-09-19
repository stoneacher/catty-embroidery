# US-401 — `EditorCore`: brick kinds, templates, addressing, indentation

**Epic**: E5 Block editor | **Estimate**: ~4 h | **Depends on**: — (M2 `ProgramModel`, shipped)

**Story**: As the developer, I want the editor's vocabulary to exist as pure values in its own target, so every later editor story is a transformation of tested types rather than a view inventing its own model.

This is the M4 counterpart of US-302: the load-bearing values land first, on the fast `swift test` gate, before any pixel exists. Nothing here is user-visible.

## What this story creates

- The **`EditorCore` target**, depending on `ProgramModel` only (ADR-033), vended through the **existing `ProgramModel` product** so the app can `import EditorCore` with no `pbxproj` change.
- **`BrickKind`** — a payload-free mirror of `Brick`, `CaseIterable` and `Sendable`. It is the spine of the milestone: palette rows, the same-kind guard on `replaceBrick` (US-402), and row labels (US-407) all key off it.
- **`BrickKind.template() -> [Brick]`** — a new brick of that kind seeded from `BrickDefaults`, returning an **array** because a loop opener yields two bricks (ADR-035).
- **`ScriptAddress` / `BrickAddress`** — index-based addressing (ADR-034), `Hashable` and `Sendable`.
- **`Script.indentDepths`** — the per-row nesting depth the list view renders as indentation, as a pure function.

## Acceptance criteria

- [ ] `EditorCore` exists as a target depending on `ProgramModel` **only** among package targets, and imports **no SwiftUI and no CoreGraphics**. **Foundation is permitted** — ADR-033 restricts *package dependencies*, not the standard library, and US-404 puts `Data`/`JSONEncoder` in this target, so a Foundation ban would make that story unbuildable. This mirrors what ADR-022 means by `StagePreview` being "Foundation-only": Foundation and nothing above it. *(Corrected at Codex round 1 — the first draft said "imports no Foundation", which contradicted US-404 outright.)*
- [ ] An isolation test pins the above. **It cannot be modelled on `StagePreviewTargetIsolationTests`' mechanism**, which does not scan source imports — it binds public APIs to explicit function types, and its own comment distinguishes that from dependency enforcement. The dependency restriction is enforced by the manifest and by the build; what the test adds is a guard against a SwiftUI/CoreGraphics import creeping in, which needs a source scan or an equivalent. Choose the mechanism deliberately and say which guarantee it actually gives.
- [ ] **`import EditorCore` compiles in the app target with `project.pbxproj` unmodified.** Verified at planning time and re-verified here as the story's own first step; if it fails, stop and raise a human Xcode session rather than working around it.
- [ ] `BrickKind`'s `Brick → BrickKind` switch is **exhaustive with no `default:`** — the pattern `RunBatch.reducing` already uses — so adding a `Brick` case is a compile error rather than a silent gap.
- [ ] `BrickKind.template()` seeds every parameter from `BrickDefaults` where a constant exists, and **this story adds the ones that do not**. `BrickDefaults` holds exactly **nine** constants — `moveSteps`, `turnDegrees`, `placeAtX`, `placeAtY`, `stitchLength`, `zigZagLength`, `zigZagWidth`, `threadColorHex`, `waitSeconds` — and the palette needs more than that. The missing set, verified against `BrickValues.java` *(extended at Codex round 2, which found the first inventory still incomplete)*: a **repeat count**; a **variable name and initial value** for `setVariable`/`changeVariableBy`; an **output file name** for `writeEmbroideryToFile`; **`pointInDirection`**, which Catroid gives as `POINT_IN_DIRECTION = 90` (`BrickValues.java:41`) — note it is **not** `turnDegrees`, which is 15, so reusing the existing angle constant would ship a different default direction; and **`changeXBy`/`changeYBy`**, which Catroid gives as separate `CHANGE_X_BY`/`CHANGE_Y_BY = 10` (`:37-38`) — numerically equal to `moveSteps`, so they need their own named constants rather than accidental reuse. Each new constant is added to `BrickDefaults` **with its Catroid provenance in a comment**, matching the existing nine; where Catroid has no counterpart, say so in the comment rather than inventing a silent default. *(Codex round 1: the first draft said "seeds every parameter from `BrickDefaults`", which is impossible against the shipped nine.)*
- [ ] A loop opener's template is **two** bricks, opener then `.loopEnd`.
- [ ] `Script.indentDepths` returns one depth per brick: body bricks are deeper than their opener, a `loopEnd` sits at its **opener's** depth (not the body's), and nested loops accumulate. An **unbalanced** script — which the model permits even though no `EditAction` can create one — yields depths without trapping and without going negative.
- [ ] `BrickAddress`/`ScriptAddress` address a brick through `Program → Scene → Object → Script → index`. M4's working program is realistically one scene / one object / one script (both shipped samples are), but the address stays honest against the model that permits more.

**Not in this story**: any mutation. `EditAction` and `apply` are US-402's. This story's types are inert.

## Test-first plan

1. `EditorCore` imports no SwiftUI and no CoreGraphics — by whichever mechanism the criterion above settles on. Foundation is allowed and is **not** asserted against.
2. Every `Brick` case maps to a distinct `BrickKind`, asserted by iterating `BrickKind.allCases` and round-tripping a template through the mapping — which also proves `template()` is total.
3. `BrickKind.repeatLoop.template()` is exactly `[.repeatLoop(times: .number(…)), .loopEnd]`, and `.forever.template()` is `[.forever, .loopEnd]`.
4. Every non-loop template is exactly one brick.
5. Each template's parameter values equal the corresponding `BrickDefaults` constant — asserted against `BrickDefaults` by name, not against re-typed literals, so a change to the default cannot leave this test passing against a stale copy. It covers the **new** constants as well as the existing nine. **What it does *not* prove is that the implementation references the constant**: mutating `.number(BrickDefaults.moveSteps)` to `.number(10)` leaves it green, because the values are equal today *(Codex round 2)*. The guarantee is "the template tracks the constant if the constant changes", and the story claims only that; a structural check is the alternative if the stronger guarantee is wanted.
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
