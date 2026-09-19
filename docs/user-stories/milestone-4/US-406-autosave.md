# US-406 — Autosave to Documents

**Epic**: E6 Projects & persistence (thin) | **Estimate**: ~3 h | **Depends on**: US-404, US-405

**Story**: As a user, I want the program I am building to still be there when I come back, without ever having pressed Save.

One thin persistence slice, and no more: a **single** working program at a fixed path. The project list, create/rename/duplicate/delete, versioning UI and migration machinery all stay M5. The line to hold is *one file, one version number, refuse what you do not understand*.

## Acceptance criteria

- [ ] A `ProgramStoring` protocol (`load() throws -> Program?`, `save(_:) throws`) with a `DocumentsProgramStore` default and a hand-rolled test double — ADR-006 pattern 2, and structurally the same split US-308 used for `DSTFileWriting`. The package keeps its "no dependencies, no I/O" property: the codec is US-404's pure `ProgramDocument`, and `FileManager` is only ever touched in the app.
- [ ] **Atomic write** (`Data.write(to:options:.atomic)`), and **the previous file is never deleted on a failed encode**. A half-written program is worse than a stale one.
- [ ] **Saved on every committed edit, plus on `scenePhase` leaving `.active`.** No debounce: at ~4 KB there is nothing to debounce, and a debounce means a clock, which means injection and a test double for a problem that does not exist. The write happens off the main actor.
- [ ] **A rejected edit saves nothing.** Third time this distinction is load-bearing (undo, run-voiding, now autosave) and the third reason ADR-033 made `apply` return a result.
- [ ] **Load at launch**: a valid file restores the working program and the app opens on it. No file is not an error — it is a first launch, and the blank program from US-405 is the answer.
- [ ] **An unreadable or too-new file is refused visibly and preserved.** `unsupportedVersion` or `corrupt` → the app opens a blank program **and says so**, and the offending file is **renamed aside**, not overwritten. Clobbering a file we failed to parse is the one unrecoverable thing this story could do.
- [ ] **A save failure is surfaced, not swallowed.** M3's single best lesson is US-309's `drawn=0` capture scoring `PASS`: a silent success is worse than a loud failure. The user does not need a dialog on every hiccup, but they must not be told nothing while their work stops being saved.
- [ ] The undo stack is **not** persisted (ADR-006), and a relaunch therefore starts with `canUndo == false`. Asserted, so nobody "improves" it later without deciding to.

## Test-first plan

1. Save then load through the test double round-trips the working program as a whole value.
2. An applied edit triggers exactly one save; a **rejected** edit triggers none.
3. Leaving `.active` triggers a save even with no edit since the last one.
4. Load with no file yields the blank program and no error state.
5. Load of a `formatVersion: 2` payload leaves the working program blank, sets the visible refusal state, and **the store's file is still there** — the preservation assertion, which is the one that matters.
6. Load of a corrupt payload does the same with the corrupt reason.
7. A throwing `save` on the double surfaces a failure state rather than being swallowed.
8. After a simulated relaunch (fresh view model, same store), `canUndo` is false and the program is the saved one.
9. Two saves in a row with no intervening edit do not corrupt the file — the atomicity smoke test at the level this story can actually assert.

**Mutation targets**: a save that writes before the edit is applied (green for most of the above, one edit behind forever); "rename aside" implemented as delete-then-write.

**Real-device / simulator check in the definition of done**: force-quit the app mid-edit and relaunch. Exit criterion 3 says "including across a force-quit", and no unit test with a double proves that — this is the criterion's actual evidence.

## References

- ADR-037 (reserved — US-404 and this story write it), ADR-006 pattern 2 (injected side effects, hand-rolled doubles)
- ADR-003 — JSON as the project format
- US-308 / `DSTFileWriting` — the value/syscall split this mirrors
- ROADMAP M5 — everything this story deliberately does not build
- `Catroid/.../ScriptFragment.java:409-419`, `XstreamSerializer.java:810` — saves only on pause and back-press, so a crash mid-edit loses work; `Catty/.../ScriptCollectionViewController.m` — saves after nearly every mutation. Neither extreme is copied; this story is nearer Catty's.
