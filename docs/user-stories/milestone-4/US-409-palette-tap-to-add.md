# US-409 — The palette, tap-to-add

**Epic**: E5 Block editor | **Estimate**: ~5 h | **Depends on**: US-401, US-402, US-407

**Story**: As a user, I want to pick a brick from a palette and have it appear in my program, so I can build a design from nothing.

This is the story that satisfies exit criterion 1's "with no bundled sample involved at any point". `swift-ui-design` pass before implementation.

## What the reference does and does not give us

**The palette is ours to design.** The `embroideryDesigner` flavor **restricts nothing** — it is four lines of Gradle (`catroid/build.gradle:280-283`) flipping a checkbox default, and an embroidery user sees every stock category plus an extra one. What we port is the Embroidery **category**: `CategoryBricksFactory.kt:1039-1056`, 8 embroidery bricks (`Stitch`, `SetThreadColor`, `RunningStitch`, `ZigZagStitch`, `TripleStitch`, `SewUp`, `StopRunningStitch`, `WriteEmbroideryToFile`) plus `setupPeripheralMotionBrickList()`'s 11 motion bricks. That, intersected with what the M2 interpreter actually executes, is M4's palette.

**Tap-to-add is only half portable.** Catroid's palette is tap-only, but the tap injects the brick at the **midpoint of the visible list** and immediately enters drag mode, so the user *must* place it (`ScriptFragment.java:613-634`); Catty does the same (`ScriptCollectionViewController.m:626-631`). SwiftUI has no programmatic drag initiation, so the reference flow cannot be copied. We insert at a defined point and scroll to it. The ROADMAP's "tap-to-add, matching Catroid's flow" is therefore **half right**, and that is recorded rather than quietly reinterpreted.

## SwiftUI constraints to design against, not discover

- **`.presentationBackgroundInteraction` is mandatory**, not a nicety: tap-to-add is only comprehensible if the script list behind the sheet is visible and live while you tap.
- **Avoid `.medium`.** No API reports a sheet's current height — `Context.maxDetentValue` is readable only inside a `CustomPresentationDetent`, and `presentationDetents(_:selection:)` gives the selection, not a height. Use `.fraction` or a custom detent, **because only then can the script list be given the matching `.safeAreaInset(edge: .bottom)`**. Without that inset a freshly inserted brick lands **behind the sheet**: SwiftUI does not inset a `List` for a sheet the way it does for the keyboard.
- **On iPad a sheet is wrong.** `RootView` uses `NavigationSplitView` in `.regular`, and a sheet from the detail column covers the whole window. Use `.popover` plus `.presentationCompactAdaptation(.sheet)` — popover on regular, detented sheet on compact, one call site. Verify on both simulators; adaptation behaviour is a class this repo has been burned by.
- **ADR-023's container swap dismisses the sheet.** Hoist `isPalettePresented` into the observable model above `RootView`, where `path` and `interaction` already live — or an iPad resize loses the palette and, worse, orphans an open US-403 coalescing session.

## Acceptance criteria

- [ ] A palette listing the curated brick set, grouped, each row showing the brick as it will appear. `BrickKind` drives it (US-401), so a new brick case cannot be silently missing.
- [ ] Tapping a row applies `EditAction.insert` through the funnel and dismisses the palette.
- [ ] **The insertion point is defined and stated**: after the current selection, or at the end when there is none — **and with a loop opener selected, *inside* the loop, immediately after the opener** (ADR-035). Otherwise a loop is unfillable by tap-to-add, which is the only add gesture this milestone has.
- [ ] **Inserting a loop inserts two bricks** and the list shows both, correctly indented, immediately.
- [ ] **The newly inserted brick is visible after insertion** — scrolled to, and not behind the sheet. This is the criterion the `.fraction` + safe-area-inset decision exists to satisfy, and the one most likely to be quietly failed.
- [ ] `.loopEnd` is **not in the palette** (ADR-035).
- [ ] Popover on regular, detented sheet on compact, from one call site; presentation state hoisted above `RootView`.
- [ ] Palette rows are ≥ 44 pt, reflow at AX1, and each is a single VoiceOver element naming the brick and what it does.
- [ ] **Story-specific definition of done**: screenshots on iPhone (sheet, at two detents) and iPad (popover), plus one showing a brick inserted inside a loop.

## Test-first plan

1. The palette's rows are exactly the curated kind list, in order, and every `BrickKind` in that list has a localised non-empty name.
2. Tapping a row produces exactly one `EditAction.insert` with the expected kind and address.
3. Insertion with nothing selected appends at the end; with a leaf brick selected it inserts after it.
4. **Insertion with a loop opener selected lands inside the loop** — the resulting whole `Program` has the new brick between opener and `loopEnd`.
5. Insertion of a loop kind adds two bricks and the script validates.
6. `.loopEnd` is absent from the palette list — asserted against the list, so adding it later fails.
7. The insert path routes through `apply` and a rejected insert changes nothing.
8. The scroll target after an insert is the inserted brick's index (or, for a loop, the opener's).

## Watch item

**US-315 is scheduled immediately after this story, deliberately.** A detented sheet resizing the stage area is the same transient class — a view whose frame animates while the canvas draws — that US-315 exists to diagnose. If anything is seen here, capture it and hand it to that story rather than fixing it in passing.

## References

- ADR-039 (reserved — this story and US-407 write it), ADR-035 (the insertion rule, and `.loopEnd`'s absence), ADR-023 (the container swap), ADR-010
- `Catroid/.../CategoryBricksFactory.kt:1039-1056`, `:1080-1095` — the Embroidery category and the peripheral motion list, i.e. the parity target
- `Catroid/.../build.gradle:280-283` — the flavor that restricts nothing
- `Catroid/.../AddBrickFragment.kt:151-180`, `ScriptFragment.java:613-634` — tap-to-add, and the forced drag we cannot port
