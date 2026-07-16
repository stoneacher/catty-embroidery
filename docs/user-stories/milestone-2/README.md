# Milestone 2 — Interpreter MVP

**Status**: In progress — planned 2026-07-16.

Goal: a value-type program model (project → scene → object → scripts → bricks) plus a minimal interpreter executing headlessly — when-started script, motion bricks, repeat/wait, the eight embroidery bricks, and a formula subset (literals, arithmetic, variables). Executing a program yields an `EmbroideryStream`. Still no UI. See [ROADMAP.md](../../ROADMAP.md).

Every story is developed test-first: the tests listed in its "Test-first plan" are written and red before implementation starts.

Where the Catroid and Catty references disagree, **ADR-012 in [DECISIONS.md](../../DECISIONS.md) is the arbiter** — and the interpreter never re-implements stream semantics: dedup, interpolation, color-change, and layer rules stay owned by the engine (`EmbroideryStream` / `EmbroideryPatternManager`, ADR-012/013/015). The interpreter only *calls* them.

| Story | Title | Est. | Depends on |
|-------|-------|------|------------|
| [US-201](US-201-program-model-and-targets.md) | Program model value types and sibling targets | ~4 h | — |
| [US-202](US-202-brick-enum-and-paired-control.md) | Brick enum and flat script with paired-control invariant | ~4 h | US-201 |
| [US-203](US-203-formula-tree-and-evaluator.md) | Formula tree and evaluator | ~5 h | US-201 |
| [US-204](US-204-virtual-needle-and-motion-bricks.md) | Virtual needle and motion bricks | ~4 h | US-203 |
| [US-205](US-205-stepper-core.md) | Stepper core: compile, scheduler, events, injected clock, wait | ~5 h | US-202, US-204 |
| [US-206](US-206-embroidery-bricks-wired.md) | Embroidery bricks wired into the interpreter | ~5 h | US-205 |
| [US-207](US-207-golden-program-square.md) | Golden program: stitch a square | ~3 h | US-206 |
| [US-208](US-208-golden-program-star.md) | Golden program: stitch a star | ~3 h | US-207 |
| [US-209](US-209-pattern-to-bytes-differential.md) | Pattern→stream→bytes differential test | ~3 h | US-207 |
| [US-210](US-210-coordinate-overflow-chokepoint.md) | Coordinate overflow/±121 chokepoint | ~3 h | US-206 |

**Total: ~39 h.** Suggested order: 201 → 202 → 203 → 204 → 205 → 206 → 207 (exit criterion reachable here) → 208 → 209/210 in any order (202 and 203 may swap).

**Milestone exit criterion**: a hardcoded "stitch a square/star" program produces the expected stitch stream in unit tests, and the interpreter is incrementally consumable — execution advances step-by-step, emits ordered needle/stitch/color events, is deterministic (golden stitch-stream tests), and takes an injected clock for time-based bricks; consuming events one tick at a time yields the same stream as batch execution. Reached at US-207, demonstrated fully at US-208.

## Design summary

Decided in the M2 planning session (2026-07-16; explored per the explore-before-propose practice, journal 2026-07-09) with `swift-architect`, grounded in the Catroid canonical implementation, Catty prior art, and the M1 engine API:

- **Two sibling targets** (ADR-016): `ProgramModel` (pure value graph — Program/Scene/Object/Script/Brick/Formula — no engine dependency) and `Interpreter` (depends on `ProgramModel` + `EmbroideryEngine`; the only place model and engine meet). M4's editor and M5's persistence import `ProgramModel` without linking any embroidery/DST code.
- **Bricks are an `indirect enum`** with associated values: the brick set is deliberately closed (ADR-001), giving the interpreter an exhaustive switch, synthesized Codable for M5, and free value semantics/`Sendable` for whole-`Program` equality (ADR-006).
- **Scripts stay flat with paired control bricks** (ADR-008): `repeatLoop`/`forever` pair with a `loopEnd` marker that is never dropped from the model (M4 editor and `.catrobat` interop depend on it). The interpreter compiles the flat list internally to a linear instruction array with jump offsets (Catty `CBBackend` precedent) — an implementation detail, not model structure.
- **The needle is the object** (Catroid: the needle is the sprite): motion bricks mutate a virtual needle in ADR-007 stage space; every position change feeds the object's active stitch pattern via the engine's `RunningStitch` wrapper, and emitted points go to `EmbroideryPatternManager.addStitch(at:layer:actor:)` with `layer = zIndex`, one `ActorID` per object.
- **Deterministic time**: an injected `InterpreterClock` with a fixed logical `tickDelta`; a `wait` occupies `ceil(seconds/tickDelta)` ticks. All motion is instant, so embroidery geometry is time-independent — waits affect only event timing and multi-script interleaving. Pinned as an ADR in US-205.
- **Formulas** mirror Catroid's `FormulaElement` tree, restricted to numbers, arithmetic operators (PLUS/MINUS/MULT/DIVIDE/MOD/POW, unary minus), and user variables with object-scope-shadows-project-scope resolution. Invalid/NaN formulas throw internally; every brick catches and falls back to its Catroid default — a bad formula never halts the program.

## Documented deviations from Catroid

Deliberate, geometry-preserving deviations (everything stitch-visible stays Catroid-faithful):

| Deviation | Why |
|---|---|
| Idle once-per-tick `runningStitch.update()` omitted | With instant bricks, an update at an unchanged position crosses no threshold and moves no anchor — a geometric no-op. |
| Wall-clock waits replaced by injected logical clock | Determinism and no I/O in the package; geometry is time-independent, so the stream is identical. |
| 20 ms loop-delay throttle omitted | Pure timing throttle, zero geometric effect, and Catroid disables it while stitching anyway (`LoopAction.isLoopDelayNeeded`). |
| GoTo touch/random/other-sprite excluded | Stage-input/RNG/multi-sprite resolution has no headless meaning; parity target for M6. `placeAt`/`setX`/`setY`/`changeXBy`/`changeYBy` cover deterministic placement. |
| `WriteEmbroideryToFile` executes as a finalize marker event, no file I/O | The package performs no implicit I/O; the assembled stream is always available via `assembledStream()`, and DST materialization is the app's concern (M3/E7). The brick stays in the model for M4/M5 fidelity. |
| Zero/negative/non-finite pattern parameters are no-ops | Already pinned in ADR-014 (avoids porting Java's NaN-poison and spam behaviors). |
