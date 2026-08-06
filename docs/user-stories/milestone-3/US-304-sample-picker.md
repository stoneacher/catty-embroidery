# US-304 — Sample picker

**Epic**: E6 Projects & persistence (thin) | **Estimate**: ~2 h | **Depends on**: US-303

**Status**: Not started

**Story**: As a user, I want to pick one of the bundled designs from a list and land on its stage, so I can see something embroider without creating anything first.

Catroid has **no precedent** for this — it generates a single starter project imperatively and has no picker at all — so this screen owes nothing to the reference and is judged only against ADR-010 and the HIG. It stays deliberately thin: M5 owns the real project list (create/rename/duplicate/delete), and building picker surface now that M5 must replace would be waste.

## Acceptance criteria
- [ ] A `List` of `SampleLibrary.all` with localised names and short localised descriptions; selecting one navigates to the stage (compact) or selects into the detail column (regular), per the US-303 skeleton.
- [ ] Each row is a **single VoiceOver element** whose label includes the sample's name and description — not three separate elements the user has to swipe through.
- [ ] Rows are ≥ 44 pt tall at every Dynamic Type size, and reflow to multiple lines at AX1 rather than truncating.
- [ ] Selecting a sample publishes the chosen `SampleProgram` as the app's current selection; re-selecting the same sample re-publishes it rather than being a no-op, so a later consumer can treat selection as "start over". **Selection carries no run state** — this story is positioned before US-306, so `RunViewModel` and `RunState` do not exist yet, and resetting an actual run is US-306's acceptance criterion, not this one. (An earlier draft named `RunViewModel` here and broke the milestone's own buildability claim; Codex round 1.)
- [ ] No loading state is required (samples are in-process values, ADR-022 — the app links the builders and never decodes). The empty state is unreachable by construction, and that is **asserted, not assumed**.
- [ ] **Story-specific definition of done**: screenshots at compact and regular; row reflow checked at AX1.

## Test-first plan
1. The picker's view model exposes exactly one row per `SampleLibrary.all` entry, in library order.
2. Selecting a sample sets the current selection to that `SampleProgram`, and the selection exposes its `Program` — using only `Samples` and the US-303 shell, no run types.
3. Re-selecting the currently selected sample re-publishes the selection (observable as a change), so US-306 can hang "start over" off it.
4. Every row's accessibility label is non-empty, localised, and contains both name and description.
5. `SampleLibrary.all` is non-empty — the assertion that makes the empty state unreachable rather than merely unlikely.

## References
- ADR-010 (universal, size-class adaptive), ADR-022 (samples as an in-process product)
- ROADMAP M5 — the real project list this screen deliberately does not anticipate
- `Catroid/.../DefaultProjectHandler.java` — the one-starter-project approach, i.e. the absence of a precedent
