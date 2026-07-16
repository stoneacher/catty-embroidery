# US-201 — Program model value types and sibling targets

**Epic**: E3 Program model & interpreter | **Estimate**: ~4 h | **Depends on**: — (M1 complete)

**Status**: Planned

**Story**: As the codebase, I want a `ProgramModel` target and an `Interpreter` target wired into the package so the program tree lives beside the engine without the engine depending on it.

## Acceptance criteria
- [ ] `Package.swift` gains targets `ProgramModel` (no dependencies beyond Foundation) and `Interpreter` (depends on `ProgramModel` + `EmbroideryEngine`), plus test targets `ProgramModelTests` and `InterpreterTests` and matching library products. `EmbroideryEngine` gains **no** new dependency — the arrow points inward only (ADR-016).
- [ ] `Program`, `Scene`, `Object`, `Script`, `ScriptHeader`, `Variable` as `Sendable`, `Equatable`, `Codable` value types. `Program` carries a `formatVersion: Int` (ADR-003 versioned format). `Script` holds a `header: ScriptHeader` (M2: only `.whenStarted` — Catroid's `StartScript`, whose `WhenStartedBrick` header contributes no action) and a flat `bricks` array (ADR-008; the `Brick` type itself lands in US-202).
- [ ] `Object` carries `startX`/`startY`/`startHeading` (defaults 0, 0, 0° — ADR-007 center origin, 0° = up) and `zIndex: Int`, plus object-scoped `variables`. The interpreter later maps object → `ActorID` and `zIndex` → engine `layer` (US-110 seams).
- [ ] `ProgramModel` holds **no engine types**: positions are plain `Double`s (converted to `StagePoint` by the interpreter); colors are hex `String`s (parsed by the interpreter via `ThreadColor(hexString:)`).

## Test-first plan
1. Codable round-trip: encode → decode a nested `Program` (scene, two objects with variables and empty scripts) and assert whole-value equality (ADR-006 discipline).
2. Equality: two independently constructed identical programs compare equal; a one-field difference (e.g. `zIndex`) compares unequal.
3. Defaults: a default-initialized `Object` sits at (0, 0) heading 0°, zIndex 0.
4. Target isolation: `InterpreterTests` compiles with `import ProgramModel` and `import EmbroideryEngine`; `ProgramModel`'s sources and `ProgramModelTests` never import the engine (build-level guarantee — the target has no such dependency to import).

## References
- `Catroid/.../content/Project.java`, `Scene.java`, `Sprite.java`, `Script.java`, `StartScript.java`, `bricks/WhenStartedBrick.java`
- ADR-003, ADR-006, ADR-007, ADR-008, ADR-016 in `docs/DECISIONS.md`
