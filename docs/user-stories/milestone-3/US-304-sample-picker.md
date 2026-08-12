# US-304 — Sample picker

**Epic**: E6 Projects & persistence (thin) | **Estimate**: ~2 h | **Depends on**: US-303

**Status**: Done — 2026-08-12. 14 app tests green (8 new), 489 engine tests
green, SwiftLint `--strict` clean, CI green on all three required checks. Red
proven first: 7 tests, 10 compile errors, and CI red on that commit by design.
Screenshots: iPhone 17 compact (list, pushed stage, **AX1** reflow,
**extra-small** for the 44 pt floor) and iPad Pro 11 regular (empty detail,
selected row + filled detail, **dark mode**, **AX1** in the narrow sidebar).

**Four things this story turned out to owe that its own text did not list**, all
implemented:

1. **The ADR-023 hoist.** `RootView`'s doc comment and ADR-023 both assign it
   here by name — hoist the selection and the path above the size-class branch —
   and the acceptance criteria never mentioned it. It is most of the work.
2. **Deleting US-303's placeholder "Stage" link.** A row that navigates *is* the
   selection that link stood in for.
3. **The stage had to learn the selection.** Without it the app told a user who
   had just picked a design that *No Design Selected*, and the regular-width
   screenshot evidencing "selects into the detail column" would have been
   identical before and after the tap — an acceptance criterion with no possible
   evidence. It *names* the design; drawing it stays US-305's.
4. **`showsSelection`.** Reported by Sebastian from the simulator: after Back in
   compact the row stayed highlighted. The model keeping the selection is
   intended and US-306 depends on it; the highlight was not — a tint means "this
   is what the detail column is showing", true only in the split layout, and iOS
   clears a pushed row's highlight on return for the same reason. The container
   states the flag, so the picker still never reads the size class.

**The load-bearing implementation decision, because the obvious alternative is
green and wrong**: rows are `Button`s rather than `List(selection:)`.
`List(selection:)` gives the sidebar highlight for free but does not guarantee
that re-tapping the **already-selected** row writes the binding — undocumented,
collection-view-backed behaviour. With it, criterion 4 would have been
unreachable through the UI while every unit test passed. The cost is a
hand-rolled selected-row treatment, which the in-loop review then found three
real defects in (colour-only selection, no press feedback, dead zones in the row
insets) — all fixed, and all of them costs the first version of the comment had
not listed.

**Estimate**: ~2 h as written; ~4 h actual, the difference being the hoist and
the presentation fixes above.

No manual Ink/Stitch verification is needed — this story emits no DST bytes and
touches no engine path.

**Story**: As a user, I want to pick one of the bundled designs from a list and land on its stage, so I can see something embroider without creating anything first.

Catroid has **no precedent** for this — it generates a single starter project imperatively and has no picker at all — so this screen owes nothing to the reference and is judged only against ADR-010 and the HIG. It stays deliberately thin: M5 owns the real project list (create/rename/duplicate/delete), and building picker surface now that M5 must replace would be waste.

## Acceptance criteria
- [x] A `List` of `SampleLibrary.all` with localised names and short localised descriptions; selecting one navigates to the stage (compact) or selects into the detail column (regular), per the US-303 skeleton.
- [x] Each row is a **single VoiceOver element** whose label includes the sample's name and description — not three separate elements the user has to swipe through.
- [x] Rows are ≥ 44 pt tall at every Dynamic Type size, and reflow to multiple lines at AX1 rather than truncating.
- [x] Selecting a sample publishes the chosen `SampleProgram` as the app's current selection; re-selecting the same sample re-publishes it rather than being a no-op, so a later consumer can treat selection as "start over". **Selection carries no run state** — this story is positioned before US-306, so `RunViewModel` and `RunState` do not exist yet, and resetting an actual run is US-306's acceptance criterion, not this one. (An earlier draft named `RunViewModel` here and broke the milestone's own buildability claim; Codex round 1.)
- [x] No loading state is required (samples are in-process values, ADR-022 — the app links the builders and never decodes). The empty state is unreachable by construction, and that is **asserted, not assumed**.
- [x] **Story-specific definition of done**: screenshots at compact and regular; row reflow checked at AX1.

**Not verified by screenshot, stated rather than glossed**: an actual
compact↔regular resize (iPad Split View). The survival claim rests on ownership
above the branch plus the path/selection unit tests. **Also not run: VoiceOver
itself.** The single-element requirement was checked by capturing the runtime
accessibility snapshot of the running app on both devices — it reports exactly
one `button` per row carrying the composed label — which covers the structure
but not the spoken order or the `.isSelected` trait.

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
