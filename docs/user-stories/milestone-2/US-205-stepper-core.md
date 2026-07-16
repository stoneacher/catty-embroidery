# US-205 — Stepper core: compile, scheduler, events, injected clock, wait

**Epic**: E3 Program model & interpreter | **Estimate**: ~5 h | **Depends on**: US-203, US-204

**Status**: Planned

**Story**: As a caller, I want to run a program headlessly one tick at a time with an injected clock, getting ordered events, such that batch and step-by-step consumption agree.

This is the milestone's tightest story (scheduler + clock + events + compilation land together). If it runs hot, split wait/clock into a follow-up story rather than growing this one.

## Acceptance criteria
- [ ] Each flat script compiles once into a linear instruction array with jump offsets: `repeatLoop` → counter init + conditional back-jump, `forever` → unconditional back-jump, `loopEnd` → no-op landing pad (Catty `CBBackend` precedent). The **model** stays the flat paired list — compilation is internal (ADR-008).
- [ ] `Interpreter(program:clock:)` value type with `step() -> StepOutcome` (`.ticked([InterpreterEvent])` / `.finished`), `run(maxTicks:) -> [InterpreterEvent]`, and `isFinished`. All state (needle, program counters, variable store, clock cursor) lives inside the value — no globals, no reference types.
- [ ] `InterpreterEvent`: `needleMoved`, `stitch`, `colorArmed`, `waited`, `finalizeRequested` — ordered, `Equatable` (embroidery cases are produced from US-206 on; the enum lands here).
- [ ] One tick = round-robin over every runnable `whenStarted` script (all objects, creation order): each script executes instant bricks until it finishes or blocks on an unelapsed `wait` (Catroid/libgdx: instant actions complete within one `act`; many bricks per tick; multiple start scripts interleave per tick).
- [ ] `wait(seconds:)` uses the injected `InterpreterClock { tickDelta }`: the interpreter advances a logical clock by `tickDelta` per tick; a wait occupies `ceil(seconds / tickDelta)` ticks. No wall-clock anywhere in the package. **Pin the tick/clock semantics as an ADR in this story's close-out.**
- [ ] `setVariable`/`changeVariableBy` mutate the interpreter's variable store, visible to later formula evaluation (scoping per US-202).
- [ ] Error semantics: a throwing formula in any brick applies that brick's **per-brick Catroid action fallback** (US-204's table; e.g. `moveNSteps` catch-and-skip, `placeAt` zero-substitution; the `wait` and `repeatLoop` fallbacks are verified against `WaitAction`/`RepeatAction` and pinned in this story) and execution continues — a bad formula never halts the program (Catroid catches `InterpretationException` per action).

## Test-first plan
1. Empty program: first `step()` returns `.finished`; `run()` returns `[]`.
2. One script, three moves: three `needleMoved` events in brick order, all in one tick.
3. `wait(0.1)` under a fake clock with `tickDelta` 0.05 blocks for exactly 2 ticks, then the script resumes.
4. Two `whenStarted` scripts (same object, then different objects) interleave per tick in creation order — event order asserted.
5. `repeatLoop(3)` runs its body exactly 3×; nested loops multiply; `forever` is bounded by `run(maxTicks:)` and never terminates on its own.
6. `setVariable` then `moveNSteps(variable)` moves by the stored value; `changeVariableBy` accumulates.
7. Equivalence (exit-criterion test, structural): concatenating every `step()` batch equals `run()`'s events for the same program.

## References
- `Catty/src/Catty/PlayerEngine/Backend/CBBackend.swift` (flatten-to-instructions precedent), `Catroid/.../common/ThreadScheduler.java`, `content/Look.java` (`act`), `content/actions/RepeatAction.kt`, `WaitAction.java`
- ADR-008 in `docs/DECISIONS.md`; roadmap M2 exit criterion
