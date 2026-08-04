# US-306 — Run lifecycle: driver, `AsyncStream`, batching, play/stop, needle

**Epic**: E4 Stage & preview | **Estimate**: ~5 h | **Depends on**: US-302, US-305

**Status**: Not started

**Story**: As a user, I want to press play and watch the needle lay stitches, and press stop and still have my design, so the preview is a live run rather than a static picture.

`Interpreter` is a `Sendable` struct with `mutating func step()`, so the driver owns it by value off `@MainActor` and batches its events across. Two reference lessons shape this story: Catroid's adaptive sub-stepping is an *anti*-throttle that must not be ported, and Catty's stop path tears down the object graph its own share code reads — so "export still works after stop" is an acceptance criterion here, not a hope.

## Acceptance criteria
- [ ] `InterpreterDriver` owns the `Interpreter` value in a non-`@MainActor` context, loops **`step()`** — not `run(maxTicks:)`, which cannot break on a *stitch* budget — and yields one `RunBatch` per frame's worth of work into an `AsyncStream`.
- [ ] `AsyncStream` uses **unbounded buffering**, never `.bufferingNewest`: dropping a batch would lose stitches permanently from an append-only list. Back-pressure is adequate because the producer self-paces and `apply(batch)` is O(batch).
- [ ] `ticksPerFrame` defaults to **1**, with a `maxStitchesPerFrame` cap for when it is raised. The budget is not theoretical: one tick emits 51 stitches in sample 1 and 106 in a triple-stitch design (measured at planning), and up to ADR-014's 1 000 000 cap in principle.
- [ ] The view model performs **exactly one** observable mutation per batch. A test proves the mutation count equals the *batch* count, not the stitch count — this is the roadmap's "batched before mutating observable state", made checkable.
- [ ] `RunState` is `idle | running | finished(.programFinished | .stoppedByUser | .stitchLimitReached)`. **There is no `failed` case** — ADR-018 guarantees the interpreter never halts (every bad-formula path continues with a per-brick fallback; `FormulaError.notANumber` is caught, not propagated), so nothing in the run path can fail. `failed` belongs to `ExportState` in US-308. This deliberately corrects ROADMAP.md's four-case enum rather than shipping a case with no producer.
- [ ] `forever` never terminates on its own, so the app owns the stop: no hard tick cap, a generous stitch cap that resolves to `.stitchLimitReached`.
- [ ] The run `Task` is cancellable; the driver checks `Task.isCancelled` each batch; `onTermination` finishes the continuation.
- [ ] **The terminal batch always carries `assembledStream()`** — on natural finish, on the stitch cap, *and* on cancellation. Catty's `Stage.stopProject()` calls `removeAllChildren()` and `project?.removeReferences()`, destroying the graph `shareDST` reads; making the export model part of the terminal batch closes that hazard by construction. At 0.64 ms per 50k call (measured), once per run is free.
- [ ] The stage keeps rendering in `.finished` (Catroid precedent: `StageListener.render()` still calls `stage.draw()` whenever `!finished`, regardless of pause).
- [ ] `reset()` is one assignment, because the interpreter is a value type — contrast Catroid's three separate resets (`embroideryPatternManager.clear()` twice, `resetDrawingState()`, `resetEmbroideryThreadColor()`) and Catty's reload-from-disk.
- [ ] Pacing sits behind an injected `RunPacing` interface (ADR-006 pattern 2): a display implementation sleeps ~1/60 s, an immediate implementation returns instantly so a test drains a whole run deterministically without sleeping.
- [ ] Needle indicator: greenfield on both platforms (Catroid's needle is an ordinary sprite with a PNG; Catty has zero occurrences of "needle" in `src/`). Judged on ADR-009 cost and accessibility, not parity. It must **not** be announced continuously by VoiceOver.
- [ ] **Story-specific definition of done**: play/stop ≥ 44 pt with localised labels and accessibility labels that change with state; **Reduce Motion does not disable the stitch animation** — that is the feature's content, not decoration — it disables transform springs and the fit-to-screen re-animation.
- [ ] Close-out records the batching numbers discovered by watching real samples animate: `ticksPerFrame`, `maxStitchesPerFrame`, the stitch cap, and the `tickDelta = 1/60` coupling.

## Test-first plan
1. With immediate pacing, a full sample run drains to `.finished(.programFinished)` and the display list count equals that sample's stitch-event count from US-301.
2. Observable-mutation count equals batch count, not stitch count (spy on the view model's apply path).
3. Cancelling mid-run leaves `.finished(.stoppedByUser)`, a non-empty display list, **and** a non-nil export model.
4. A `forever` program stops at the stitch cap with `.stitchLimitReached` and does not hang.
5. `reset()` returns `.idle`, empties the display list and clears the export model; a second `play()` reproduces the identical display list (determinism).
6. `wait(1)` under `tickDelta = 1/60` occupies 60 batches. ADR-018's accumulating clock may produce a one-tick drift — if it appears, pin it rather than rounding it away.
7. Screenshots mid-run and post-run.

## References
- `Catroid/.../common/ThreadScheduler.java` (pause as `state != RUNNING`), `StageListener.render():576-600` — the `deltaActionTimeDivisor` anti-throttle: up to 50 `act()` passes per frame, *increasing* when the pass is fast. **Do not port.**
- `Catty/src/Catty/PlayerEngine/Stage/Stage.swift:69-79` + `CBPlayerConfig.swift:27` — drain-every-2nd-frame, the one sound piece of Catty's pipeline; `Stage.swift:299-309` — teardown-before-share, the anti-goal this story closes
- ADR-006 (injected side effects), ADR-009, ADR-014 (the per-update stitch cap), ADR-018 (tick/clock semantics), ADR-021 (the event payload this consumes)
