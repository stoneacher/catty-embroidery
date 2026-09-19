# US-406 — Autosave to Documents

**Epic**: E6 Projects & persistence (thin) | **Estimate**: ~3 h | **Depends on**: US-404, US-405

**Story**: As a user, I want the program I am building to still be there when I come back, without ever having pressed Save.

One thin persistence slice, and no more: the project list, create/rename/duplicate/delete, versioning UI and migration machinery all stay M5. The line to hold is *one version number, refuse what you do not understand*.

## The multi-window problem, which "one file" does not survive

**This app ships more than one window, deliberately.** `UIApplicationSupportsMultipleScenes` is `true` and `WindowRootView` owns `@State private var model = AppModel()` **per scene** — a documented decision with its own reasoning (`CatrobatEmbroideryApp.swift:11-40`, itself the product of an earlier cross-vendor round): App-scoped state would make selecting a design in window A move window B, and after US-306 would make two windows restart each other's runs.

So a naive "single working program at a fixed path" **loses data** *(Codex round 1)*. Concrete case: open two windows on program P; edit window A to Q, which autosaves Q; then background window B, whose mandatory lifecycle save writes its **unchanged P over Q**. Atomicity does not help — both writes are well-formed, and the later one wins.

**This story owes a policy, chosen before implementation.** The options, cheapest first:

1. **One shared working document**: hoist the program above the per-window models so both windows edit one value. Simplest persistence, but it re-introduces exactly the cross-window coupling `WindowRootView`'s comment rejects, and would need that comment revisited rather than contradicted.
2. **Save only the window the user last edited** — a last-writer-wins rule made explicit, with unchanged windows never writing. Cheap, and it makes the lifecycle save conditional on that window having applied an edit.
3. **Per-scene files**, keyed by scene session ID. Honest for multi-window, and closest to what M5 will want, but it starts building the document management M5 owns.

**Recommendation: option 2 for M4** — it is the smallest change that stops the loss, it needs no new document model, and it leaves M5's design space open. Whichever is chosen, the decision goes in ADR-037 with the rejected alternatives, because "the app has one working program" is an assumption the rest of M4 leans on.

## Acceptance criteria

- [ ] A `ProgramStoring` protocol (`load() throws -> Program?`, `save(_:) throws`) with a `DocumentsProgramStore` default and a hand-rolled test double — ADR-006 pattern 2, and structurally the same split US-308 used for `DSTFileWriting`. The package keeps its "no dependencies, no I/O" property: the codec is US-404's pure `ProgramDocument`, and `FileManager` is only ever touched in the app.
- [ ] **Atomic write** (`Data.write(to:options:.atomic)`), and **the previous file is never deleted on a failed encode**. A half-written program is worse than a stale one.
- [ ] **Saved on every committed edit, plus on `scenePhase` leaving `.active`** — subject to the multi-window policy above, so a window that has applied no edit does not write. No debounce: at ~4 KB there is nothing to debounce, and a debounce means a clock, which means injection and a test double for a problem that does not exist.
- [ ] **Writes are ordered, or carry a revision that makes a stale write a no-op.** The write happens off the main actor, so two saves can complete out of order: edit A schedules save A, edit B schedules save B, B lands first, A then atomically replaces it — every save succeeded and the relaunch restores **A** *(Codex round 1)*. Serialise the writes or version them; either is fine, and doing neither is not.
- [ ] **A rejected edit saves nothing.** Third time this distinction is load-bearing (undo, run-voiding, now autosave) and the third reason ADR-033 made `apply` return a result.
- [ ] **Load at launch**: a valid file restores the working program and the app opens on it. No file is not an error — it is a first launch, and the blank program from US-405 is the answer.
- [ ] **An unreadable or too-new file is refused visibly and preserved.** `unsupportedVersion` or `corrupt` → the app opens a blank program **and says so**, and the offending file is **renamed aside**, not overwritten. Clobbering a file we failed to parse is the one unrecoverable thing this story could do.
- [ ] **Preservation is asserted on the original bytes at the preserved location**, not on "a file still exists at the original path" — which would also pass if load deleted the document and the subsequent blank-program autosave recreated the path *(Codex round 1)*. Assert the bytes, and assert them **after** a lifecycle save has had its chance to run.
- [ ] **If renaming aside fails, the blank program must not autosave over the original.** Define the behaviour rather than leaving the unpreserved file exposed to the very next write.
- [ ] **A save failure is surfaced, not swallowed.** M3's single best lesson is US-309's `drawn=0` capture scoring `PASS`: a silent success is worse than a loud failure. The user does not need a dialog on every hiccup, but they must not be told nothing while their work stops being saved.
- [ ] The undo stack is **not** persisted (ADR-006), and a relaunch therefore starts with `canUndo == false`. Asserted, so nobody "improves" it later without deciding to.

## Test-first plan

1. Save then load through the test double round-trips the working program as a whole value.
1b. Two windows, per the chosen multi-window policy: window A edits to Q, window B backgrounds unchanged, and the stored program is **Q**. The test that fails against the first draft's design.
2. An applied edit triggers exactly one save; a **rejected** edit triggers none.
3. Leaving `.active` triggers a save **from a window that has applied an edit**. Under the recommended policy a window that has applied none does **not** write — that is test 1b's point, and this item is written to match the policy rather than against the first draft's unconditional rule.
4. Load with no file yields the blank program and no error state.
5. Load of a `formatVersion: 2` payload leaves the working program blank, sets the visible refusal state, and **the original bytes are still readable at the preserved location** after a lifecycle save has run — not merely "a file exists at the original path", which a delete-and-recreate would satisfy.
6. Load of a corrupt payload does the same with the corrupt reason.
7. A throwing `save` on the double surfaces a failure state rather than being swallowed.
8. After a simulated relaunch (fresh view model, same store), `canUndo` is false and the program is the saved one.
9. Two saves in a row with no intervening edit do not corrupt the file — the atomicity smoke test at the level this story can actually assert.
10. **Ordering**: two saves of *different* programs whose completions are deliberately reversed leave the **later edit** on disk. Written with different values because saving the same value twice cannot detect a reordering.
11. Rename-aside failure leaves the original bytes intact and does not overwrite them with a blank program.

**Mutation targets**: a save that writes before the edit is applied (green for most of the above, one edit behind forever); "rename aside" implemented as delete-then-write.

**Real-device / simulator check in the definition of done**: force-quit the app mid-edit and relaunch. Exit criterion 3 says "including across a force-quit", and no unit test with a double proves that — this is the criterion's actual evidence.

## References

- ADR-037 (reserved — US-404 and this story write it), ADR-006 pattern 2 (injected side effects, hand-rolled doubles)
- ADR-003 — JSON as the project format
- US-308 / `DSTFileWriting` — the value/syscall split this mirrors
- ROADMAP M5 — everything this story deliberately does not build
- `Catroid/.../ScriptFragment.java:409-419`, `XstreamSerializer.java:810` — saves only on pause and back-press, so a crash mid-edit loses work; `Catty/.../ScriptCollectionViewController.m` — saves after nearly every mutation. Neither extreme is copied; this story is nearer Catty's.
