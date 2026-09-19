# US-405 — The working program replaces the sample selection

**Epic**: E5 Block editor | **Estimate**: ~5 h ⚠️ | **Depends on**: US-402, US-403

**Story**: As a user, I want the app to hold *my* program rather than a read-only sample, so that everything the editor does has something to edit — and so picking a sample means "start from this" rather than "look at this".

**Nothing new is visible on screen when this story ends.** It is the milestone's US-303: a refactor that makes every later story possible. ⚠️ It is also the story most likely to exceed its estimate — it changes a type five views read and touches five app test files. If it measures over ~5 h, split the `StageView(sample:) → title` narrowing out as **US-405b** rather than letting it run.

## What breaks, precisely

`AppModel.selection: SampleSelection?` wraps a `SampleProgram` (a `SampleID` plus a `Program`). An edited program has no `SampleID`, so:

- `StageView(sample:)` uses it for the navigation title and empty state — it must take a title and a `Program`.
- `AppModel.isSelected(_:)` compares `SampleID` for the picker highlight — **after the first edit that highlight lies.**
- `exporter.name = sample.id.resourceName` must be re-sourced.
- Affected app tests: `AppModelTests`, `SampleLinkageTests`, `SampleRowAccessibilityTests`, `StageViewWiringTests`, `ExportWiringTests`.

**What does *not* break, and it is the lucky part of M3's design**: `RunViewModel.play(_ program: Program)` already takes a `Program`, and `Interpreter(program:clock:)` takes it **by value** — it compiles the scripts and builds independent runtime stores rather than retaining the `Program` and reading through it. Either way the editor's later mutations **cannot reach a running interpreter**. Nothing in `InterpreterDriver`, `PreviewRunState`, `RunUpdate` or `RunTermination` changes. *(Codex round 1 corrected the mechanism: the first draft said the run "holds its own immutable copy", which overstates what `Interpreter` retains. The isolation conclusion is unaffected.)*

## The thing that actually goes stale

`PreviewRunState.exportModel` is captured at termination and `ExportViewModel` **eagerly writes a file** — ADR-026 made preparation eager because `ShareLink` needs its item at construction. Nothing today invalidates it. So without this story's rule, a user could edit a program and share a `.dst` describing the program they no longer have.

**The rule (ADR-038): any *applied* `EditAction` voids the run**, by calling the `runner.reset()` path `select(_:)` already calls. That path already cancels the consumer, bumps ADR-027's generation so buffered frames from the voided run cannot land, clears the display list and needle, and fires `onRunDiscarded → exporter.discard()`, which deletes the prepared temp file.

Chosen over the alternative — let the run finish and gate export on a version stamp threaded through `RunUpdate`/`RunTermination` plus a fourth `ExportControl.readiness` reason — because that is strictly more machinery for a preview the user has already invalidated. And it is honest in ADR-021's sense: the preview is a preview of *the program*; the program changed, so the preview is void. ADR-027 closed "export after stop must still work"; this opens "export after edit must not silently work".

## Acceptance criteria

- [ ] An `EditorViewModel` (`@Observable`, `@MainActor`) owns the working `Program`, the US-403 undo stack, and the single `apply(_:)` entry point. **No view mutates the program** (ADR-006 pattern 1).
- [ ] `AppModel`'s selection is generalised from `SampleSelection` to the working program plus a **`provenance: SampleID?`**, which is **cleared on the first applied edit**. The picker highlight therefore stops claiming a program is a sample once it is not.
- [ ] Picking a sample loads a **copy** into the working program — editing it never mutates `SampleLibrary`, which is a `let` of in-process values shared process-wide. Asserted, because value semantics make this true by construction and a future refactor could make it false silently.
- [ ] A **blank program** path exists (one scene, one object, one empty `whenStarted` script), since M4's whole point is building from nothing. It is what the app shows with no sample picked.
- [ ] **An applied edit calls `runner.reset()`; a rejected edit does not.** Both asserted — the second is the reason ADR-033 made `apply` return a result rather than throw.
- [ ] **`reset()` from an edit must not call `interaction.followFit()`** the way `select(_:)` does. Re-fitting the camera every time the user nudges a parameter would be unusable. This is a real divergence between two callers of one path and is the detail most likely to be missed.
- [ ] Every existing app test passes or is deliberately updated, with each update explained. A silently rewritten assertion is how a refactor hides a regression.

## Test-first plan

1. The editor view model's `apply` of a valid action updates the working program to the expected whole value and pushes one undo entry.
2. `apply` of a rejected action leaves the program **identical**, pushes nothing, and does not reset the run.
3. An applied edit clears `provenance`; loading a sample sets it.
4. Loading a sample twice re-publishes (US-304's "start over" contract still holds) and resets the undo stack.
5. Editing a loaded sample leaves `SampleLibrary.all`'s copy unchanged.
6. An applied edit calls the discard path: the run is idle, the display list empty, and the exporter has discarded its prepared file.
7. An applied edit does **not** re-fit the camera; `select(_:)` still does.
8. The blank program has exactly one scene, one object, one empty script, and passes `Script.validate()`.

## References

- ADR-038 (reserved — this story writes it), ADR-027 (the discard path and the generation bump it reuses), ADR-026 (eager export preparation, the reason staleness matters)
- ADR-021 — the preview is a preview of the program
- ADR-006 pattern 1 — views never mutate the tree
- US-304 — the re-selection contract that must survive
