# US-204 — Virtual needle and motion bricks

**Epic**: E3 Program model & interpreter | **Estimate**: ~4 h | **Depends on**: US-202, US-203

**Status**: Planned

**Story**: As the interpreter, I want a virtual needle that motion bricks move in ADR-007 stage space, emitting one `NeedleUpdate` per motion — no stitching yet.

## Acceptance criteria
- [ ] `VirtualNeedle { position, heading }` lives in the `Interpreter` target and operates in ADR-007 stage space (center origin, y-up, degrees, 0° = up). The needle is the object — Catroid has no separate needle; embroidery reads the sprite's position.
- [ ] `moveNSteps`: `dx = steps · sin(heading)`, `dy = steps · cos(heading)` (Catroid `MoveNStepsAction`; direction 0° = up, 90° = right, clockwise positive).
- [ ] `turnRight` **adds** degrees, `turnLeft` **subtracts** (Catroid `TurnRight/LeftAction` via `changeDirectionInUserInterfaceDimensionUnit`); `pointInDirection` sets absolute heading. Headings normalized mod 360 exactly, matching the ADR-014 pattern-layer discipline.
- [ ] `placeAt(x:y:)` teleports (Catroid compiles PlaceAt as a zero-duration glide — instantaneous); `setX`/`setY` set one axis; `changeXBy`/`changeYBy` accumulate.
- [ ] Every executed motion brick produces exactly one `NeedleUpdate(position:heading:)` (the engine's pattern-input type; patterns derive geometry from heading, not the movement vector).
- [ ] Bad-formula fallback is **per-brick, mirroring the corresponding Catroid action** (there is no universal "needle unchanged" rule): `moveNSteps`/`turnLeft`/`turnRight`/`pointInDirection`/`setX`/`setY`/`changeXBy`/`changeYBy` catch and perform no mutation (`MoveNStepsAction`/`SetXAction` catch-and-skip); **`placeAt` substitutes 0 for the failed coordinate** — it compiles to a zero-duration `GlideToAction`, whose failed x/y interpretation becomes `0f`, so a bad x with a good y places the needle at (0, y). The story ships this as an explicit per-brick fallback table; execution always continues.

## Test-first plan
1. Move 10 at heading 0° → (0, 10); at heading 90° → (10, 0).
2. `turnRight(90)` then move 10 advances +x; `turnLeft(90)` mirrors to −x; turns accumulate and normalize mod 360.
3. `pointInDirection(180)` is absolute (not relative); a subsequent move follows it.
4. `placeAt(100, 200)` teleports; `setX`/`setY` change one axis only; `changeXBy(5)` twice accumulates to +10.
5. Per-brick fallback: NaN/throwing formula in `moveNSteps` → needle position and heading unchanged; throwing x with valid y in `placeAt` → needle at (0, y) (the GlideToAction zero-substitution, not a no-op).

## References
- `Catroid/.../content/actions/MoveNStepsAction.java`, `TurnLeftAction.java`, `TurnRightAction.java`, `PointInDirectionAction.java`, `content/ActionFactory.java` (`createPlaceAtAction` = glide duration 0), `conditional/GlideToAction.kt` (failed coordinate interpretation → `0f`), `SetXAction.java`, `ChangeXByNAction.java`, `content/Look.java` (direction conventions)
- ADR-007, ADR-014 in `docs/DECISIONS.md`; `EmbroideryEngine` `NeedleUpdate` doc comment (heading vs movement vector)
