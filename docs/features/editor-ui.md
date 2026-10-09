# Editor UI

**Status**: In progress — 2026-10-09 | **Epic**: E5 (+ E6 thin) | **Branch**: `feature/editor-ui`

**Goal**: finish the block editor. A user builds a program from nothing in the app (palette, parameters, reorder, delete), can undo and redo *everything* from every surface the platform offers, and runs and exports it as `.dst`.

This feature **absorbs the rest of Milestone 4** (ADR-041). US-401…US-410 and the carried US-312/314/315 are done and merged (PR #51–#66). What M4 still owed is listed below; [`user-stories/milestone-4/`](../user-stories/milestone-4/) stays the detailed record, and US-411's file is the spec for its slice.

**In scope**: US-411 (undo surfaced, totality proof), M4's exit criteria, M4's deferred final verification, and any editor-UI defects found along the way. **Out**: variables beyond what US-410 shipped, the brick backend / parity set (M6 scope), project management (M5 scope) — each is its own feature.

**Brief review**: not needed — the semantics are pinned by US-411 (itself reviewed in M4 planning) and ADR-036/038.

## Acceptance criteria

M4's exit criteria, carried verbatim in substance:

- [ ] A program can be built from nothing — palette, parameters, reorder — then run and exported as `.dst`, with no bundled sample involved.
- [ ] **Every** editor mutation is undoable, proved by a test that *enumerates* `EditAction`'s cases rather than listing them by hand.
- [ ] The working program survives a relaunch including a force-quit, and a file the app cannot understand is refused and preserved rather than clobbered.
- [ ] No sequence of adds, reorders and deletes can produce a script that fails `Script.validate()`, asserted as a property over generated sequences.

Plus every acceptance criterion in [US-411](../user-stories/milestone-4/US-411-undo-surfaced.md) (the `UndoManager` bridge, executed before it is specified; the whole-program-replacement funnel; VoiceOver announcements; the totality proof; undo/redo consequences).

## Slices and test-first outline

1. **Undo surfaced (US-411)** (risky: no — app and editor layer, no DST/engine/format change) — tests: US-411's test-first plan, items 1–8 (enumeration over all six `EditAction` cases incl. `declareVariable`, redo, disabled states, `nil` `UndoManager`, `loadProgram` from all three callers, announcements, run/export/autosave consequences, bridge state, coalesced sessions). ADR-036, ADR-038, ADR-032 invariants 2 and 4. Mutations: drop one `EditAction` case's fixture, skip the bridge sync after a toolbar undo, skip the autosave or run-void on undo — each must turn a test red.
2. **Pair-invariant soak** (risky: no) — a long randomised sequence of palette adds, reorders and deletes driven through the view models, asserting `Script.validate()` after every step. Mutation: break pair-awareness in one reorder path; the soak must find it.
3. **Exit-criteria sweep** (risky: only if a gap touches the program format) — check criteria 1 and 3 against what US-405…US-410 shipped; any gap becomes a slice here rather than a new story.

## Verification at handover

- [ ] Simulator screenshots: undo/redo enabled and disabled, plus a shake-to-undo check (or a recorded finding that it does not reach the bridge).
- [ ] **The bundled manual accessibility pass** over the whole editor — VoiceOver (custom actions behind the rotor: "rotate to Actions, then swipe"), Dynamic Type, Reduce Motion — plus the items US-410 deferred to it (opened variable menu, iPad popover, swatches, row action during sheet dismissal). Record what was not run.
- [ ] **Ink/Stitch check of a hand-built design** — the first time the editor is in the provenance chain of an exported file.
- [ ] `swift-documenter` pass and the knowledge-graph drift check (read the 2026-09-18 journal entry on `--update` cost first).
- [ ] Codex loop, cap 5.

## Human-owned

- [ ] Apple Developer Program enrolment for the TestFlight usability checkpoint (open since 2026-09-19, owner Sebastian). Blocks the checkpoint, not this feature.

## References

[M4 README](../user-stories/milestone-4/README.md), [US-411](../user-stories/milestone-4/US-411-undo-surfaced.md), ADR-006, ADR-032, ADR-036, ADR-038, ADR-040.
